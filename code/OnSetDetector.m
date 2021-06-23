classdef OnSetDetector < audioPlugin & matlab.System
    % OnSet Detector
    
    %#codegen      
    properties
        DownsampleFact = 1
        FFTLength = 512 
    end
    
    methods (Access = protected)
        
        function [flag, ODF_out] = stepImpl(obj, x, x_old, ODF_in)
%%          Downsample the signal and apply FFT   
     
            x_rs = resample(x, 1, obj.DownsampleFact);
            x_rs_old = resample(x_old, 1, obj.DownsampleFact);
            
            win = hann(length(x_rs));
            win_a = circshift(win, length(x_rs)/2);
            x_rs = x_rs .* win_a;
            X = fft(x_rs,obj.FFTLength);  
            X_old = fft(x_rs_old,obj.FFTLength);
            
%%          ODF computation
            Mp = 10; %number of peak partials
            
            ODF_pad = 0;
            S_dB = 20*log10(abs(X));
            S_dB_old = 20*log10(abs(X_old));
            [~, peak_bin] = findpeaks(S_dB(1:end/2), 'SortStr','descend', 'NPeaks', Mp);            
            [~, peak_bin_old] = findpeaks(S_dB_old(1:end/2), 'SortStr','descend', 'NPeaks', Mp);            
            
            % remove 'no peaks found' warning
            warning('off', 'signal:findpeaks:largeMinPeakHeight'); 
            
            peak_bin = sort(peak_bin);
            peak_bin_old = sort(peak_bin_old);
            
            if ~isempty(peak_bin) && ~isempty(peak_bin_old)
                c = min(length(peak_bin), length(peak_bin_old));
                for i = 1:c
                    partial = abs( abs(X(peak_bin(i))) - abs(X_old(peak_bin_old(i))) );
                    ODF_pad = ODF_pad + partial;
                end

                ODF_out = ODF_in; 
                ODF_out(end) = ODF_pad;
                sigma_th = 0.5 * median(ODF_out) + 1 * mean(ODF_out);

                if (ODF_out(end) <= ODF_out(end-1)) && (ODF_out(end-1) >= ODF_out(end-2))
                    if ODF_out(end-1) > sigma_th
                        flag = 1;
                    else
                        flag = 0;
                    end
                else
                    flag = 2;
                    ODF_out = ODF_in; 
                    ODF_out(end) = ODF_pad;
                end
            
            else 
                flag = 3;
                ODF_out = ODF_in; 
                ODF_out(end) = ODF_pad;
            end
        end

    end
end