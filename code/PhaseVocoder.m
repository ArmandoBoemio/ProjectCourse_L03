classdef PhaseVocoder < audioPlugin & matlab.System
    % Phase Vocoder
    
    %#codegen      
    properties
        SampleRate = 480000
        DownsampleFact = 1
        FFTLength = 512 
        CutOffFreq = 180
        NumHarmonics = 4
        Gain = 1
    end
    
    methods (Access = protected)
        
        function y = stepImpl(obj, x)
%%          Initialize Variables
            Fs_reduced = obj.SampleRate / obj.DownsampleFact;
            
            th_level = -80; 
            obj.NumHarmonics = 7;
            ROI_size_hz = 30; 
            ROI_size_bins = round(ROI_size_hz*obj.FFTLength/Fs_reduced); 
            if mod(ROI_size_bins,2) == 0
                ROI_size_bins = ROI_size_bins + 1;
            end
            ROI_win = tukeywin(ROI_size_bins,0.75);
            ROI_win(ROI_win==0) = 1e-3; 
            
            bark_env = zeros(obj.FFTLength,1);

            numBands = 7;
            range = [0, Fs_reduced/2];
            [fb,cf] = designAuditoryFilterBank(Fs_reduced, ...
                                            "FrequencyScale","bark", ...
                                            "FFTLength",obj.FFTLength, ...
                                            "NumBands",numBands, ...
                                            "FrequencyRange",range);
            cf_bins = round(cf*obj.FFTLength/Fs_reduced) + 1;
            fb(:,end) = [];
            
            f0max_bins = (obj.CutOffFreq) * obj.FFTLength/Fs_reduced;
            f0min_bins = (31) * obj.FFTLength/Fs_reduced;
            
            range_search = floor(f0min_bins:f0max_bins);            
            
%%          Downsample the signal and apply FFT   
            x_rs = resample(x, 1, obj.DownsampleFact);
            
            win = hann(length(x_rs));
            win_a = circshift(win, length(x_rs)/2);
            x_rs = x_rs .* win_a;
            
            X = fft(x_rs,obj.FFTLength);
            X = X ./ obj.FFTLength;           
            
%%          Harmonic generation
            S_dB = 20 * log10(abs(X));
            [~, peak_bin] = findpeaks(S_dB(range_search), 'SortStr','descend', 'MinPeakHeight',th_level);            
            
            % remove 'no peaks found' warning
            warning('off', 'signal:findpeaks:largeMinPeakHeight');
            
            X_mag = abs(X(1:end/2));
            bark = fb * X_mag;
            xq=cf_bins(1):cf_bins(end);
            bark_env(xq) = interp1(cf_bins,bark,xq,'pchip');
            
            if ~isempty(peak_bin)
                peak_bin = peak_bin(1) + floor(f0min_bins);
                
                bark_env = 20 * log10(bark_env);
                
                % Apply gain correction
                g_max = 5;
                g_min = -2;
                scale = (g_max-g_min)/(5-1);
                offset = -1*(g_max-g_min)/(5-1) + g_min;
                G = obj.Gain * scale + offset;
                harm_gain_dB = 20 + G;                
                
                
                bark_env(xq) = bark_env(xq) / max(bark_env(xq)) * (S_dB(peak_bin) + harm_gain_dB);

                start_value=bark_env(floor(cf_bins(1)+1));

                fixed_low_env = zeros(obj.FFTLength,1).*(-Inf);
                fixed_high_env = zeros(obj.FFTLength,1).*(+Inf);
                fixed_low_env(1:floor(cf_bins(1))) = -Inf;
                fixed_high_env(1:floor(cf_bins(1))) = +Inf;
                fixed_low_env(floor(cf_bins(1))+1:obj.FFTLength) = start_value-10*((0:obj.FFTLength-floor(cf_bins(1))-1)/floor(cf_bins(1)));
                fixed_high_env(floor(cf_bins(1))+1:obj.FFTLength) = start_value-2*((0:obj.FFTLength-floor(cf_bins(1))-1)/floor(cf_bins(1)));           
                
                % Parabolic peak interpolation
                if (peak_bin > 1) && (peak_bin < (length(S_dB)))
                    alpha = S_dB(peak_bin - 1);
                    beta  = S_dB(peak_bin);
                    gamma = S_dB(peak_bin + 1);
                                    
                    p = (alpha - gamma) / (2 * (alpha - 2 * beta + gamma));
                    peak_bin_interp = peak_bin + p;
                    real_peak = beta - ( 0.25 * p * ( alpha - gamma ) );
                end
                
                ROI_delta = floor(ROI_size_bins/2);
                ROI_left = peak_bin-ROI_delta;
                ROI_right = peak_bin+ROI_delta;
                X_ROI = X(ROI_left:ROI_right);
                X_ROI_mag = abs(X_ROI);
                X_ROI_phase = angle(X_ROI);
                
                 for h = 1:obj.NumHarmonics
                    harm_freq = (h+1) * peak_bin_interp;
                    if harm_freq < length(X)/2
                        
                        % Pitch shift
                        binshift = harm_freq-peak_bin_interp;
                        
                        shift_left = ROI_left+floor(binshift);
                        shift_right = ROI_right+floor(binshift);

                        X_ROI_phase = unwrap(X_ROI_phase);
                        X_ROI_phase_shift = (h+1) * X_ROI_phase;

                        % Timbre matching
                        timbre = bark_env(round(harm_freq)+1);
                        weight = timbre;

                        low_weight = fixed_low_env(round(harm_freq)+1);
                        high_weight = fixed_high_env(round(harm_freq)+1);
                        if timbre < low_weight
                            weight = low_weight;
                        elseif timbre > high_weight
                            weight = high_weight;
                        end
                        if weight > th_level
                            X_ROI_mag_shift = X_ROI_mag .* (10^((weight-real_peak)/20));
                           X(shift_left:shift_right) = (abs(X(shift_left:shift_right))+((X_ROI_mag_shift).*ROI_win)).*exp(1i*X_ROI_phase_shift);
                        end            
                    end
                 end
                 
%%              Signal reconstruction
                X = [X(1:end/2); flipud(conj(X(1:end/2)))];
                y = real(ifft(X(1:end/2),obj.FFTLength)) .* obj.FFTLength;
                y = y(1:size(x_rs,1));            
                y = y .* win;
                y = resample(y, obj.DownsampleFact, 1); 
            else
                y = real(ifft(X(1:end/2),obj.FFTLength)) .* obj.FFTLength;
                y = y(1:size(x_rs,1));
                y = y .* win;
                y = resample(y, obj.DownsampleFact, 1);             
            end
        end
    end
end