classdef (StrictDefaults)VBE_Main < audioPlugin & matlab.System
    % AudioOutputEnhancer  Audio enhancer for low frequencies of an audio signal based
    % on single channel sub bands division.
    %
    % Project Course 2021
    %
    % 
    
    %   Copyright 2021
    
    %#codegen
    
    %----------------------------------------------------------------------
    % Public properties
    %----------------------------------------------------------------------
    properties
        SampleRate = 44100
        CrossCutOff = 180
        HarmCutOff = 800
        Gain = 2.5
        Mode = VBE_mode.NLD
        DrySwitch = true
    end
    
    properties (Access = private)
        BufferSize
        processingFrame = []
        x_lp_1 = []
        
        pCrossover
        
        pNLD
        pPV
        pHybrid
        
        pLowpassFilter
        pHighpassFilter
    end
    
    %----------------------------------------------------------------------
    % Constant properties
    %----------------------------------------------------------------------
    properties (Constant, Hidden)
        % audioPluginInterface manages the number of input/output channels
        % and also instantiates the value class, audioPluginParameter to
        % generate plugin UI parameters.
        PluginInterface = audioPluginInterface(...
            'InputChannels',2,...
            'OutputChannels',2,...
            'PluginName','VirtualBassEnhancer',...
            audioPluginParameter('CrossCutOff','Mapping',{'log',130 250}, ...
            'Style', 'rotaryknob', 'Layout', [1 1]), ...
            audioPluginParameter('HarmCutOff','Mapping',{'log',600 1000 }, ...
            'Style', 'rotaryknob', 'Layout', [1 2]), ...
            audioPluginParameter('Gain','Mapping',{'lin',1 5 }, ...
            'Style', 'rotaryknob', 'Layout', [3 1]), ...
            audioPluginParameter('Mode', 'Mapping', {'enum', 'NLD', 'Phase Vocoder', 'Hybrid'}, ...
            'Style', 'dropdown', 'Layout', [3 2]),...
            audioPluginParameter('DrySwitch', ...
            'Mapping', {'enum','Bypass','On'}, ...
            'Layout',[1,3], ...
            'Style','vtoggle', ...
            'DisplayNameLocation','none'), ...
            audioPluginGridLayout('RowHeight', [100 20 100 20], ...
            'ColumnWidth', [100 100 100], 'Padding', [10 10 10 30]),...
            'BackgroundImage', audiopluginexample.private.mwatlogo);
        
    end
    
    methods (Access = protected)
        
        function z = stepImpl(obj,x)
  
            Fs = obj.SampleRate;
            Fc = Fs/2;

%%          Generate 2 channels stereo signal if nChannel ~= 2
            stereo_check = size(x,2);
            if stereo_check == 1
                x_stereo = [x, x];
            elseif stereo_check ~= 2
                x_stereo = x(:,1:2);
            else
                x_stereo = x;
            end

%%          Generate processing frame
        %Divide signal in sub-bands
            [x_lp, x_hp] = obj.pCrossover(x_stereo);
            obj.processingFrame = circshift(obj.processingFrame,-obj.BufferSize(1), 1);
            obj.processingFrame(end-obj.BufferSize(1)+1:end, 1:2) = x_lp;
            obj.processingFrame(end-obj.BufferSize(1)+1:end, 3:4) = x_hp;
%%          
            x_lp = obj.processingFrame(1:obj.BufferSize(1), 1:2);
            x_hp = obj.processingFrame(1:obj.BufferSize(1), 3:4);

            % Bypass switch
            if obj.DrySwitch   
                
                x_lp_mono = sum(x_lp, 2) / 2; 
            
%%              Switching VBE mode 
                switch (obj.Mode)
                    case VBE_mode.NLD
                        x_harm = obj.pNLD(x_lp_mono);
                    case VBE_mode.PV
                        x_harm = obj.pPV(x_lp_mono);
                    case VBE_mode.Hybrid
                        x_harm = obj.pHybrid(x_lp_mono, obj.x_lp_1);
                        
                    otherwise
                        x_harm = obj.pNLD(x_lp_mono);                    
                end
                
                obj.x_lp_1 = x_lp_mono;
                
%%             Hi-pass inaudible frequencies / Low-pass harmonic spectrum
               [Bl,Al] = designVarSlopeFilter(48, obj.HarmCutOff/Fc);
               x_lp = obj.pLowpassFilter(x_harm, Bl, Al);

               [Bh,Ah] = designVarSlopeFilter(24, 120/Fc, 'hi');
               x_lp = obj.pHighpassFilter(x_lp, Bh, Ah);
               
               % Generate stereo signal
               x_lp = [x_lp x_lp];
               
            end
            
%%          Reconstruct output            
            z = x_lp + x_hp;
            
        end
        
        function setupImpl(obj, x)
            [buffer_len, n_inputs] = size(x);
            obj.BufferSize = [buffer_len, n_inputs];
            
            n_buffers = 4; % corresponds to a 75% overlap in the STFT
            obj.processingFrame = zeros(buffer_len * n_buffers, n_inputs);
            obj. x_lp_1 = zeros(buffer_len * n_buffers, 1);
            
            obj.pCrossover  = crossoverFilter(1,'CrossoverSlopes',24);
            obj.pCrossover.CrossoverFrequencies = obj.CrossCutOff;
            
            
            obj.pNLD = VBE_NLD;
            obj.pNLD.Gain = obj.Gain;
            
            obj.pPV = VBE_PV;
            obj.pPV.Gain = obj.Gain;
            obj.pPV.CrossCutOff = obj.CrossCutOff;
            
            obj.pHybrid = VBE_Hybrid;
            obj.pHybrid.Gain = obj.Gain; 
            obj.pHybrid.CrossCutOff = obj.CrossCutOff;

            obj.pLowpassFilter = dsp.BiquadFilter( ...
                                    "SOSMatrixSource","Input port", ...
                                    "ScaleValuesInputPort",false);     
            obj.pHighpassFilter = dsp.BiquadFilter( ...
                                    "SOSMatrixSource","Input port", ...
                                    "ScaleValuesInputPort",false);  
        end
        
        function resetImpl(obj)
            fs = getSampleRate(obj);
            obj.SampleRate = fs;

            obj.pCrossover.SampleRate = fs;                        

            obj.pNLD.SampleRate = fs;
            obj.pPV.SampleRate = fs;
            obj.pHybrid.SampleRate = fs;

            reset(obj.pCrossover);
            
            reset(obj.pNLD);
            reset(obj.pPV);
            reset(obj.pHybrid)
            
            reset(obj.pLowpassFilter);
            reset(obj.pHighpassFilter);
        end
        
        function processTunedPropertiesImpl(obj)
            
            if obj.pCrossover.CrossoverFrequencies ~= obj.CrossCutOff
                obj.pCrossover.CrossoverFrequencies = obj.CrossCutOff;
            end
          
            if obj.pNLD.Gain ~= obj.Gain
                obj.pNLD.Gain = obj.Gain;
            end
            
            if obj.pPV.Gain ~= obj.Gain
                obj.pPV.Gain = obj.Gain;
            end
            if obj.pPV.CrossCutOff ~= obj.CrossCutOff
                obj.pPV.CrossCutOff = obj.CrossCutOff;
            end
            
            if obj.pHybrid.Gain ~= obj.Gain
                obj.pHybrid.Gain = obj.Gain;
            end
            if obj.pHybrid.CrossCutOff ~= obj.CrossCutOff
                obj.pHybrid.CrossCutOff = obj.CrossCutOff;
            end

        end
            
    end
        
end