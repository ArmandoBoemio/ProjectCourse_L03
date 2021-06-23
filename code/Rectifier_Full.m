classdef Rectifier_Full < audioPlugin & matlab.System

    % Full Wave Rectifier

    %#codegen
    
    methods (Access = protected)
        
        function y = stepImpl(~,x)
            
            % Initialization
            y = zeros(size(x));
            
            for i = 1:size(y,2)            
                fullrect_idx = (x(:,i) > 0);
                y(fullrect_idx, i) = x(fullrect_idx);
%                 y(~fullrect_idx, i) = -x(~fullrect_idx);
                y(~fullrect_idx, i) = 0;
            end

        end
    end
end