classdef ValidationView < handle
    %VALIDATIONVIEW One explicit research workflow, embedded in the workspace.
    properties
        app
        st001
        synthetic
        benchmarks
        dataRoot
        python
        runButton
        cancelButton
        loadButton
        status
        report
        outputFolder=""
        lastStudy=[]
        running=false
        lastStage=""
    end
    methods
        function obj=ValidationView(app,parent)
            obj.app=app; options=ssdot.validation.defaultOptions();
            grid=uigridlayout(parent,[5 1]); grid.RowHeight={38,36,36,48,'1x'};
            choices=uigridlayout(grid,[1 6]); choices.ColumnWidth={150,160,220,135,90,'1x'}; choices.Padding=[0 0 0 0];
            obj.st001=uicheckbox(choices,'Text','All ST001 recordings','Value',true);
            obj.synthetic=uicheckbox(choices,'Text','Known-source tests','Value',true);
            obj.benchmarks=uicheckbox(choices,'Text','Independent/public benchmarks','Value',true);
            obj.runButton=uibutton(choices,'Text','Run validation','FontWeight','bold','ButtonPushedFcn',@(~,~)app.controller.perform(@()obj.runValidation()));
            obj.cancelButton=uibutton(choices,'Text','Cancel','Enable','off','ButtonPushedFcn',@(~,~)obj.requestCancel());
            obj.loadButton=uibutton(choices,'Text','Open existing report','ButtonPushedFcn',@(~,~)obj.chooseReport());
            row=uigridlayout(grid,[1 3]); row.ColumnWidth={165,'1x',100}; row.Padding=[0 0 0 0];
            uilabel(row,'Text','External benchmark inputs');
            obj.dataRoot=uieditfield(row,'text','Value',char(options.externalDataRoot),'Tooltip','Public recordings/models stay outside Git. Published checksums are required.');
            uibutton(row,'Text','Browse','ButtonPushedFcn',@(~,~)obj.chooseDataRoot());
            row=uigridlayout(grid,[1 2]); row.ColumnWidth={165,'1x'}; row.Padding=[0 0 0 0];
            uilabel(row,'Text','Python for benchmark adapter');
            obj.python=uieditfield(row,'text','Value',char(options.pythonExecutable),'Tooltip','Python with NumPy, SciPy and h5py. No system packages are installed automatically.');
            obj.status=uilabel(grid,'Text','Explicit research study. Full Research settings; no automatic tuning. Results distinguish numerical checks, known-source accuracy and physiological uncertainty. Public assets may be downloaded with integrity checks.','WordWrap','on');
            obj.report=uihtml(grid);
            obj.report.HTMLSource='<html><body style="font:16px sans-serif;padding:24px"><h2>Scientific validation</h2><p>Run the selected study sections or open a saved report. The application keeps the numerical configuration unchanged and reports failed scientific criteria as evidence, not exceptions to hide.</p></body></html>';
        end
        function runValidation(obj,options)
            assert(~obj.app.controller.busy,'SSDOT:Busy','Wait for current processing or cancel it first.');
            if nargin<2
                options=ssdot.validation.defaultOptions(); options.st001=obj.st001.Value;
                options.synthetic=obj.synthetic.Value; options.benchmarks=obj.benchmarks.Value;
                options.externalDataRoot=string(obj.dataRoot.Value); options.pythonExecutable=string(obj.python.Value);
            end
            assert(options.st001 || options.synthetic || options.benchmarks,'SSDOT:ValidationSelection','Select at least one study section.');
            if strlength(string(options.outputFolder))==0
                stamp=string(datetime('now','TimeZone','UTC','Format','yyyyMMdd-HHmmss'));
                options.outputFolder=fullfile(options.outputRoot,"scientific-"+stamp+"-"+extractBefore(string(java.util.UUID.randomUUID()),9));
            end
            obj.outputFolder=string(options.outputFolder); obj.running=true; obj.lastStage="";
            obj.app.controller.beginWork(); cleanup=onCleanup(@()obj.finish());
            obj.setBusy(true); obj.cancelButton.Enable='on';
            obj.status.Text='Starting scientific validation. Current reconstruction settings and cached results are unchanged.';
            obj.app.banner.Text='Scientific validation in progress. Full-resolution, explicitly configured experiments.';
            drawnow;
            obj.lastStudy=ssdot.validation.runStudy(options,@(status)obj.receiveProgress(status));
            obj.status.Text=char(obj.lastStudy.state+" - report saved in "+obj.outputFolder);
            obj.report.HTMLSource=char(fullfile(obj.outputFolder,'report.html'));
            obj.app.controller.log('Scientific validation '+obj.lastStudy.state+': '+obj.outputFolder);
            obj.app.statusLabel.Text=char(obj.lastStudy.state);
        end
        function receiveProgress(obj,status)
            obj.status.Text=sprintf('%s | elapsed %.0f s',status.stage,status.elapsedSeconds);
            obj.app.progressLabel.Text=char(status.stage); obj.app.statusLabel.Text='Scientific validation';
            if status.total>0, obj.app.progressGauge.Value=100*min(1,max(0,status.completed/status.total)); end
            if obj.lastStage~=status.stage, obj.app.controller.log(status.stage); obj.lastStage=status.stage; end
            drawnow limitrate;
            if obj.app.controller.cancelRequested, obj.writeCancellation(); end
        end
        function requestCancel(obj)
            if ~obj.running, return; end
            obj.app.controller.requestCancel(); obj.writeCancellation();
            obj.status.Text='Cancel requested - the current blocking read/factorization finishes before stopping. Completed outputs are retained.';
        end
        function writeCancellation(obj)
            if ~isfolder(obj.outputFolder), mkdir(obj.outputFolder); end
            fid=fopen(fullfile(obj.outputFolder,'cancel.request'),'w'); if fid>=0, fclose(fid); end
        end
        function setBusy(obj,busy)
            controls={obj.st001,obj.synthetic,obj.benchmarks,obj.dataRoot,obj.python,obj.runButton,obj.loadButton};
            for k=1:numel(controls), controls{k}.Enable=matlab.lang.OnOffSwitchState(~busy); end
            obj.cancelButton.Enable=matlab.lang.OnOffSwitchState(busy && obj.running);
        end
        function finish(obj)
            obj.running=false;
            if isvalid(obj.app) && isvalid(obj.app.figure)
                obj.setBusy(false); obj.app.controller.finishWork();
            end
        end
        function chooseDataRoot(obj)
            folder=uigetdir(obj.dataRoot.Value,'External benchmark input cache');
            if ~isequal(folder,0), obj.dataRoot.Value=folder; end
        end
        function chooseReport(obj)
            [file,folder]=uigetfile('report.html','Open scientific validation report',fullfile(ssdot.app.projectRoot(),'results','validation'));
            if ~isequal(file,0), obj.report.HTMLSource=fullfile(folder,file); obj.outputFolder=string(folder); obj.status.Text='Viewing saved report: '+string(folder); end
        end
    end
end
