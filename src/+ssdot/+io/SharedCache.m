classdef SharedCache < handle
    %SHAREDCACHE Bounded, session-local immutable numeric preparation and hashes.
    properties
        limitBytes = 512*2^20
        bytes = 0
        hits = 0
        misses = 0
        modelLoads = 0
    end
    properties (Access = private)
        entries
        fileHashes
        clock = 0
    end
    methods
        function obj = SharedCache(limitBytes)
            if nargin
                obj.limitBytes = limitBytes;
            end
            obj.entries = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.fileHashes = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        function [value, found] = get(obj, key)
            key = char(key);
            found = isKey(obj.entries, key);
            value = [];
            if ~found
                obj.misses = obj.misses + 1;
                return;
            end

            item = obj.entries(key);
            obj.clock = obj.clock + 1;
            item.used = obj.clock;
            obj.entries(key) = item;
            value = item.value;
            obj.hits = obj.hits + 1;
        end

        function put(obj, key, value)
            key = char(key);
            info = whos('value');
            if info.bytes > obj.limitBytes
                return;
            end

            if isKey(obj.entries, key)
                obj.evict(key);
            end
            % Evict least recently used entries until the new value fits.
            while obj.bytes + info.bytes > obj.limitBytes && obj.entries.Count > 0
                keys = obj.entries.keys;
                lastUses = cellfun(@(name) obj.lastUse(name), keys);
                [~, oldest] = min(lastUses);
                obj.evict(keys{oldest});
            end

            obj.clock = obj.clock + 1;
            obj.entries(key) = struct('value', value, 'bytes', info.bytes, 'used', obj.clock);
            obj.bytes = obj.bytes + info.bytes;
        end

        function releasePreparations(obj)
            % Retain immutable anatomical/model reads; release recomputable workspace.
            keys = obj.entries.keys;
            for index = 1:numel(keys)
                if ~startsWith(keys{index}, 'model:')
                    obj.evict(keys{index});
                end
            end
        end

        function identity = filesIdentity(obj, files)
            % Rehash a file when its path, byte count or filesystem write time changes.
            identities = strings(size(files));
            for index = 1:numel(files)
                file = java.io.File(char(files(index)));
                path = char(file.getCanonicalPath());
                assert(file.isFile(), 'SSDOT:MissingInputs', 'Required input missing: %s', path);
                stamp = [double(file.length()), double(file.lastModified())];

                if isKey(obj.fileHashes, path)
                    item = obj.fileHashes(path);
                else
                    item = [];
                end
                if isempty(item) || ~isequal(item.stamp, stamp)
                    item = struct('stamp', stamp, 'hash', ssdot.io.fileHash(path));
                    obj.fileHashes(path) = item;
                end
                identities(index) = string(path) + ":" + item.hash;
            end
            identity = ssdot.io.valueHash(identities);
        end

        function identity = algorithmIdentity(obj)
            % Identity of every source file that shapes a reconstruction result.
            projectRoot = ssdot.app.projectRoot();
            packageRoot = fullfile(projectRoot, 'src', '+ssdot');
            reconFiles = sortedPaths(dir(fullfile(packageRoot, '+recon', '*.m')));
            readers = {'checkWorkflowInputs', 'loadAtlas', 'loadForwardModel', 'loadSensitivity', 'readRun', ...
                'recordingProbe', 'atlasProbe', 'recordingFiles', 'valueHash', 'assertCompatibleProbe'};
            readerFiles = string(cellfun(@(name) fullfile(packageRoot, '+io', [name '.m']), readers, ...
                'UniformOutput', false))';
            configFiles = string(fullfile(packageRoot, '+app', 'defaultConfig.m'));
            homerFiles = sortedPaths(dir(fullfile(projectRoot, 'external', 'homer', '**', '*.m')));
            files = [reconFiles(:); readerFiles; configFiles; homerFiles];
            identity = ssdot.io.valueHash([string(version); obj.filesIdentity(files)]);
        end
    end
    methods (Access = private)
        function used = lastUse(obj, key)
            item = obj.entries(key);
            used = item.used;
        end

        function evict(obj, key)
            item = obj.entries(key);
            obj.bytes = obj.bytes - item.bytes;
            remove(obj.entries, key);
        end
    end
end

function paths = sortedPaths(listing)
    paths = sort(arrayfun(@(file) string(fullfile(file.folder, file.name)), listing));
end
