function tests=testNumerics
    tests=functiontests(localfunctions);
end

function setupOnce(t)
    root=fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root,'src'));
    ssdot.app.initializeEnvironment();
end

function testGaussianKernel(t)
    expected=[1 exp(-0.5)]; expected=expected/sum(expected);
    verifyEqual(t,ssdot.recon.buildGaussianKernels([0 0 0],[0 0 0;1 0 0],1,'cpu'),expected,'AbsTol',1e-12);
    verifyEqual(t,ssdot.recon.downsampleVertices([1 2 3],1),[1 2 3]);
end

function testForwardDesignAgainstPhysicalModel(t)
    rng(12);
    G=struct('G_brain',rand(2,3),'G_scalp',rand(1,2));
    A=struct('Amatrix_brain',optics(2,3),'Amatrix_scalp',optics(2,2));
    T=ssdot.recon.buildTemporalMatrix(rand(4,4,2),rand(3,2,2));
    Y=zeros(16,1);
    [Hb,Hs]=ssdot.recon.buildDesignMatrix(A,G,T,Y,'cpu',struct());
    b=rand(24,1);
    expected=zeros(2,4,2);
    for wavelength=1:2
        for time=1:4
            for tissue=1:2
                if tissue==1, spatial=G.G_brain; optical=A.Amatrix_brain; offset=0;
                else, spatial=G.G_scalp; optical=A.Amatrix_scalp; offset=16; end
                    nG=size(spatial,1);
                    for hb=1:2
                        if hb==1, design=T.T_HbO_brain; name=sprintf('w%d_HbO',wavelength);
                        else, design=T.T_HbR_brain; name=sprintf('w%d_HbR',wavelength); end
                            concentration=zeros(size(spatial,2),1);
                            for g=1:nG
                                for basis=1:4
                                    coefficient=b(offset+(hb-1)*nG*4+(g-1)*4+basis);
                                    concentration=concentration+spatial(g,:)'*design(time,basis)*coefficient;
                                end
                            end
                            expected(:,time,wavelength)=expected(:,time,wavelength)+optical.(name)*concentration;
                        end
                    end
                end
            end
            verifyEqual(t,[Hb,Hs]*b,expected(:),'AbsTol',1e-12);
            report=ssdot.app.gpuDiagnostics(false);
            if report.available
                [Hg,Sg]=ssdot.recon.buildDesignMatrix(A,G,T,Y,'gpu',1,1);
                verifyEqual(t,Hg,Hb,'AbsTol',1e-10); verifyEqual(t,Sg,Hs,'AbsTol',1e-10);
            else
                verifyError(t,@()ssdot.recon.buildDesignMatrix(A,G,T,Y,'gpu',1,1),'SSDOT:GPUUnavailable');
            end
        end

        function testConcentrationMultipleBasisAndConditions(t)
            G=struct('G_brain',[1 0;0 1],'G_scalp',1);
            T=ssdot.recon.buildTemporalMatrix(ones(4,4,2),cat(3,[1 2;3 4],[5 6;7 8]));
            b=1:24;
            C=ssdot.recon.reconstructConcentrations(G,T,b,1,true,'cpu');
            verifyEqual(t,numel(C.intensity_HbO),2);
            verifyEqual(t,C.intensity_HbO{1},[1 2;5 6]*T.t_HbO_brain');
            verifyEqual(t,C.intensity_HbO{2},[3 4;7 8]*T.t_HbO_brain');
            verifyEqual(t,C.intensity_HbR{1},[9 10;13 14]*T.t_HbR_brain');
            verifyEqual(t,C.intensity_HbO_scalp{2},[19 20]*T.t_HbO_brain');
            verifyEqual(t,size(C.intensity_HbO{1}),[2 2]);
        end

        function testWeightedNormalsAndInverse(t)
            rng(4);
            H=randn(12,7); Y=H*(1:7)';
            R=spdiags((1:12)',0,12,12);
            [hy,hh]=ssdot.recon.buildNormalEquations(H(:,1:2),H(:,3:4),sparse(H(:,5)),sparse(H(:,6:7)),Y,2,'cpu',R);
            verifyEqual(t,hy,H'*R*Y,'AbsTol',1e-10);
            verifyEqual(t,hh,H'*R*H,'AbsTol',1e-10);
            for mode=[1 2 3]
                cfg=struct('alpha',1e-12,'beta',0,'regularization',mode,'device','cpu');
                b=ssdot.recon.solveReconstruction(H(:,1:2),H(:,3:4),sparse(H(:,5)),sparse(H(:,6:7)),Y,cfg,R);
                verifyEqual(t,b,1:7,'AbsTol',1e-7);
            end
        end

        function testNoiseWeightOrdering(t)
            cfg=struct('regularization',2,'noise_variance',[1 2 4 8]);
            R=ssdot.recon.measurementPrecision(zeros(2,3),zeros(2,3),cfg);
            verifyEqual(t,full(diag(R)),[1;.5;1;.5;1;.5;.25;.125;.25;.125;.25;.125]);
        end

        function testMaskAndProjectionAdapters(t)
            mask=ones(102,1); mask(51)=0; mask(102)=0;
            verifyEqual(t,ssdot.recon.activeMeasurements({mask},100),true(100,1));
            list=[(1:100)' ones(100,1) ones(100,1) ones(100,1)];
            list(12,3)=0;
            expected=true(100,1); expected(12)=false;
            verifyEqual(t,ssdot.recon.activeMeasurements({list},100),expected);
            verifyError(t,@()ssdot.recon.activeMeasurements(ones(9,1),100),'SSDOT:MeasurementMask');
            T=ssdot.recon.buildTemporalMatrix(ones(4,1,2),cat(3,[0;1;1],[0;2;2]));
            C=struct('intensity_HbO',{{[2 3 4;5 6 7]}},'intensity_HbR',{{[8 9 10;11 12 13]}});
            [O,R]=ssdot.recon.projectToVertices(struct('T',T,'M',struct('mask_brain',[1 3]),'Conc',C),4);
            verifyEqual(t,O,[3;0;6;0]); verifyEqual(t,R,[9;0;12;0]);
        end

        function A=optics(nChannels,nVertices)
            A=struct('w1_HbO',rand(nChannels,nVertices),'w1_HbR',rand(nChannels,nVertices), ...
                'w2_HbO',rand(nChannels,nVertices),'w2_HbR',rand(nChannels,nVertices));
        end
