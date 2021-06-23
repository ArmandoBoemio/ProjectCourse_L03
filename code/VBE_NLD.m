classdef (StrictDefaults)VBE_NLD < audioPlugin & matlab.System
    % VBE_NLD  Audio enhancer for low frequencies of an audio signal using
    % a time domain technique. In particular, the module uses a full-wave
    % rectifier as non-linear device.
    %
    % Project Course 2021

    
    %#codegen
    properties
        SampleRate = 44100
        Gain = 1
    end
    
    properties (Access = private)
        pRectifier_Full
    end
   
    methods (Access = protected)
        
        function z = stepImpl(obj,x)
            
            % Non Linear Device 
            x_NLD = obj.pRectifier_Full(x);

            % Apply Gain
            g_max = 4;
            g_min = 1;
            scale = (g_max-g_min)/(5-1);
            offset = -1*(g_max-g_min)/(5-1) + g_min;
            G = obj.Gain * scale + offset;

            % Enhanced output
            z = x_NLD .* G; 
                
        end
        
        function setupImpl(obj)
            obj.pRectifier_Full = Rectifier_Full;              
        end
        
        function resetImpl(obj)
            fs = obj.SampleRate;
            reset(obj.pRectifier_Full);
        end
        
    end
    
end