classdef (StrictDefaults)VBE_Hybrid < audioPlugin & matlab.System
    % VBE_PV  Audio enhancer for low frequencies of an audio signal using a
    % frequency domain technique. In particular, the module uses a phase
    % vocoder to generate the pitch shifted harmonics of the fundamental.
    % It also uses a timbre matching scheme to weight the harmonics.
    %
    % Project Course 2021

    
    %#codegen
    

    properties        
        SampleRate = 44100
        CrossCutOff = 120
        Gain = 1
    end
    
    properties (Access = private)
        DownsampleFact = 16
        BufferSize
        processingFrameOld = []
        FFTLength = 4096
        ODF = []
        NumHarmonics = 4

        pODF
        pPhaseVocoder
        pRectifier_Full
    end
    
    methods (Access = protected)
        
        function z = stepImpl(obj, x, x_old)
             
%%          On-set detection and harmonic generation
            
            [flag,obj.ODF] = obj.pODF(x, x_old, obj.ODF);
            obj.ODF = circshift(obj.ODF, -1);
            obj.ODF(end) = 0;

            if flag == 0 || flag == 2
            % Phase Vocoder
                x_harm = obj.pPhaseVocoder(x);
                
            elseif flag == 1 
            % Non-linear device
                x_harm = obj.pRectifier_Full(x);
                
                % Apply Gain
                g_max = 3;
                g_min = 1;
                scale = (g_max-g_min)/(5-1);
                offset = -1*(g_max-g_min)/(5-1) + g_min;
                G = obj.Gain * scale + offset;
                x_harm = x_harm * G;

            elseif flag == 3
                x_harm = x;
            end
                       
            % Overlap and add
            x_harm = x_harm + obj.processingFrameOld;
            obj.processingFrameOld = x_harm;

%%          Refresh overlapping frames
            obj.processingFrameOld = circshift(obj.processingFrameOld, -obj.BufferSize);
            obj.processingFrameOld(end-obj.BufferSize(1)+1:end, :) = 0;
            
            % Store output buffer
            z = x_harm(1:obj.BufferSize(1));
        end
        
        function setupImpl(obj, x)
            
            [buffer_len, n_inputs] = size(x);
            obj.BufferSize = [buffer_len, n_inputs];
            
            obj.processingFrameOld = zeros(buffer_len, 1);
            
            obj.pODF = OnSetDetector;
            obj.pODF.DownsampleFact = obj.DownsampleFact;
            obj.pODF.FFTLength = obj.FFTLength;
                    
            obj.pPhaseVocoder = PhaseVocoder;
            obj.pPhaseVocoder.DownsampleFact = obj.DownsampleFact;
            obj.pPhaseVocoder.FFTLength = obj.FFTLength;
            obj.pPhaseVocoder.CutOffFreq = obj.CrossCutOff;
            obj.pPhaseVocoder.NumHarmonics = obj.NumHarmonics;
            obj.pPhaseVocoder.Gain = obj.Gain;

            obj.pRectifier_Full = Rectifier_Full; 
                        
        end

        function resetImpl(obj)
            
            Fs = obj.SampleRate;          
            obj.FFTLength = 2^nextpow2(((Fs/obj.DownsampleFact)/2)); 
            
            obj.pPhaseVocoder.SampleRate = Fs;
            
            obj.ODF = zeros(7, 1);

            reset(obj.pODF);
            reset(obj.pPhaseVocoder);            
            reset(obj.pRectifier_Full);

        end

        function processTunedPropertiesImpl(obj)
            
            if obj.pPhaseVocoder.CutOffFreq ~= obj.CrossCutOff
                obj.pPhaseVocoder.CutOffFreq = obj.CrossCutOff;
            end
            
            if obj.pPhaseVocoder.Gain ~= obj.Gain
                obj.pPhaseVocoder.Gain = obj.Gain;
            end
        end
        
    end
    
end