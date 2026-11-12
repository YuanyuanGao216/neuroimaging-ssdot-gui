classdef FigureExportTest < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addProject(~)
            root=fileparts(fileparts(mfilename('fullpath'))); addpath(root); addpath(fullfile(root,'src'));
        end
    end
    methods (Test)
        function nativeFormatsPreserveValuesAndRejectInvalidMesh(t)
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [data,options]=FigureExportTest.smallData(); options.formats=["png","pdf","fig"];
            report=ssdot.viz.exportFigures(data,fixture.Folder,options);
            t.verifyNumElements(report.files,6);
            for item=report.files, file=fullfile(fixture.Folder,item.name); t.verifyTrue(isfile(file)); info=dir(file); t.verifyGreaterThan(info.bytes,0); end
            png=imfinfo(fullfile(fixture.Folder,'hbo_condition-001.png')); t.verifyGreaterThan(png.Width,500);
            fig=openfig(fullfile(fixture.Folder,'hbo_condition-001.fig'),'invisible'); t.addTeardown(@()delete(fig));
            patches=findall(fig,'Type','patch'); t.verifyNumElements(patches,2);
            for patch=patches', t.verifyEqual(patch.FaceVertexCData,data.result.hbo); end
            t.verifyEqual(string(fig.Visible),"off");
            broken=data; broken.result.hbo=broken.result.hbo(1:3);
            t.verifyError(@()ssdot.viz.exportFigures(broken,fixture.Folder,options),'SSDOT:ResultSize');
            t.verifyError(@()ssdot.viz.exportFigures(data,fixture.Folder,options),'SSDOT:ExportExists');
        end
        function destinationProtectsInputsAndNeverOverwrites(t)
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            inputs=fullfile(fixture.Folder,'original-inputs'); mkdir(inputs); sub=fullfile(inputs,'subfolder'); mkdir(sub);
            t.verifyError(@()ssdot.io.createFigureExportFolder(inputs,string(inputs)),'SSDOT:ExportIntoInputs');
            t.verifyError(@()ssdot.io.createFigureExportFolder(sub,string(inputs)),'SSDOT:ExportIntoInputs');
            a=ssdot.io.createFigureExportFolder(fixture.Folder,string(inputs)); b=ssdot.io.createFigureExportFolder(fixture.Folder,string(inputs));
            t.verifyNotEqual(a,b); t.verifyTrue(isfolder(a) && isfolder(b));
            marker=struct('status',"cancelled",'files',{{'already-completed.png'}});
            ssdot.io.writeFigureManifest(a,marker); t.verifyEqual(jsondecode(fileread(fullfile(a,'manifest.json'))).status,'cancelled');
            missing=fullfile(fixture.Folder,'does-not-exist');
            t.verifyError(@()ssdot.io.createFigureExportFolder(missing,strings(0,1)),'SSDOT:ExportFolder');
            t.verifyFalse(isfolder(missing));
            [data,options]=FigureExportTest.smallData(); options.formats="svg";
            t.verifyError(@()ssdot.viz.exportFigures(data,fixture.Folder,options),'SSDOT:ExportFormat');
            options.formats="png";
            t.verifyError(@()ssdot.viz.exportFigures(data,missing,options),'SSDOT:ExportFolder');
        end
        function roiExportUsesExistingSelectionsAndCompatibleComparisons(t)
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [data,options]=FigureExportTest.smallData(); options.maps=false; options.rois=true;
            surface=ssdot.io.surfaceFromAtlas(data.atlas);
            a=ssdot.io.roiFromIndices(surface,1,3,'Selection A'); b=ssdot.io.roiFromIndices(surface,2,4,'Selection B');
            data.rois=[a b]; data.comparison=struct('first',1,'second',2,'mode',"overlay");
            overlay=fullfile(fixture.Folder,'overlay'); mkdir(overlay); options.formats=["png","fig"];
            report=ssdot.viz.exportFigures(data,overlay,options); t.verifyNumElements(report.files,6);
            fig=openfig(fullfile(overlay,'roi-comparison.fig'),'invisible'); t.addTeardown(@()delete(fig));
            t.verifyNumElements(findall(fig,'Type','patch'),1);
            t.verifyEqual(report.files(end).roiLabels,["Selection A";"Selection B"]);
            side=fullfile(fixture.Folder,'side'); mkdir(side); options.formats="png"; data.comparison.mode="sideBySide";
            report=ssdot.viz.exportFigures(data,side,options); t.verifyNumElements(report.files,3);
            t.verifyEqual(data.rois,[a b]);
        end
        function averagesExportTAndPMapsWithChosenSignificance(t)
            fixture=t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [data,options]=FigureExportTest.smallData(); options.formats="fig"; options.significance=0.01;
            data.result.statistics=ssdot.recon.groupStatistics(struct('hbo',{data.result.hbo,3*data.result.hbo}, ...
                'hbr',{data.result.hbr,data.result.hbr}));
            report=ssdot.viz.exportFigures(data,fixture.Folder,options);
            t.verifyEqual(sort(string({report.files.name}))',sort(["hbo_condition-001.fig";"hbr_condition-001.fig"; ...
                "hbo-tvalue_condition-001.fig";"hbo-pvalue_condition-001.fig";"hbr-tvalue_condition-001.fig";"hbr-pvalue_condition-001.fig"]));
            fig=openfig(fullfile(fixture.Folder,'hbo-tvalue_condition-001.fig'),'invisible'); t.addTeardown(@()delete(fig));
            patches=findall(fig,'Type','patch'); t.verifyEqual(patches(1).FaceVertexCData,data.result.statistics.hbo.t,'RelTol',1e-12);
            pItem=report.files(string({report.files.name})=="hbo-pvalue_condition-001.fig");
            t.verifyEqual(pItem.colorLimits,[0 0.01*256/255],'AbsTol',1e-15);
            undefined=report.files(string({report.files.name})=="hbr-tvalue_condition-001.fig");
            t.verifyEqual(undefined.colorLimits,[-1 1],'Undefined t (no variation) is shown neutral.');
        end
    end
    methods (Static,Access=private)
        function [data,options]=smallData()
            mesh=struct('vertices',[120 125 125;136 125 125;128 140 125;128 132 140], ...
                'faces',[1 2 3;1 2 4;1 3 4;2 3 4]);
            atlas=struct('fwmodel',struct('mesh',mesh),'pialsurf',struct('mesh',mesh,'mesh_reduced',mesh));
            data=struct('label',"Fixture / preserved values",'atlas',atlas, ...
                'result',struct('hbo',[1;2;3;4]*1e-10,'hbr',[-4;-3;-2;-1]*1e-10), ...
                'temporal',[],'centers',[],'rois',[],'comparison',[],'sensitivity',[],'preview',false,'signals',struct());
            options=struct('formats',"png",'dpi',72,'maps',true,'temporal',false,'kernels',false,'rois',false, ...
                'inputViews',false,'autoColor',false,'showNonRoi',true);
        end
    end
end
