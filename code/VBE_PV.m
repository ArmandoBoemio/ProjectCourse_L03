classdef (StrictDefaults)VBE_PV < audioPlugin & matlab.System
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
        NumHarmonics = 4

        pPhaseVocoder
    end
    
    methods (Access = protected)
        
        function z = stepImpl(obj,x)
            
%%          Phase Vocoder
            x_PV = obj.pPhaseVocoder(x);
            
            % Overlap and add
            x_PV = x_PV + obj.processingFrameOld;
            obj.processingFrameOld = x_PV;
            
            % Store output buffer
            x_PV = x_PV(1:obj.BufferSize(1));

%%          Refresh overlapping frames
            obj.processingFrameOld = circshift(obj.processingFrameOld, -obj.BufferSize);
            obj.processingFrameOld(end-obj.BufferSize(1)+1:end, :) = 0;
            

            z = x_PV;
        end
        
        function setupImpl(obj, x)

            [buffer_len, n_inputs] = size(x);
            obj.BufferSize = [buffer_len, n_inputs];
            
            obj.processingFrameOld = zeros(buffer_len, 1);
                                                        
            obj.pPhaseVocoder = PhaseVocoder;
            obj.pPhaseVocoder.DownsampleFact = obj.DownsampleFact;
            obj.pPhaseVocoder.FFTLength = obj.FFTLength;
            obj.pPhaseVocoder.CutOffFreq = obj.CrossCutOff;
            obj.pPhaseVocoder.NumHarmonics = obj.NumHarmonics;
            obj.pPhaseVocoder.Gain = obj.Gain;
                                    
        end

        function resetImpl(obj)
            
            Fs = obj.SampleRate;          
            obj.FFTLength = 2^nextpow2(((Fs/obj.DownsampleFact)/2)); 
            
            obj.pPhaseVocoder.SampleRate = Fs;
            
            reset(obj.pPhaseVocoder);

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