% Test bench script for 'VBE_Main'.

%% Setup Testbench

disp('Select an audio track...')

[audio_track,~] = uigetfile({'*.wav; *.mp3; *.mp4; *.m4a',...
                        'Audio file (*.wav, *.mp3, *.mp4, *.m4a)'}, ...
                        'audios\Samples\rock.wav');

play_count = 1;


%% Testbench
disp('Playing audio...')

% Create test bench input and output
fileReader = dsp.AudioFileReader('Filename', audio_track, ...
    'PlayCount', play_count, ...
    'SamplesPerFrame', 1024);

deviceWriter = audioDeviceWriter('SampleRate',fileReader.SampleRate);

% Set up the system under test
sut = VBE_Main;
setSampleRate(sut,fileReader.SampleRate);

% Open parameterTuner for interactive tuning during simulation
tuner = parameterTuner(sut);
drawnow

% Stream processing loop
nUnderruns = 0;
while ~isDone(fileReader)
    % Read from input, process, and write to output
    in = fileReader();
    out = sut(in);
    nUnderruns = nUnderruns + deviceWriter(out);
    
    % Process parameterTuner callbacks
    drawnow limitrate
end

% Clean up
release(sut)
release(fileReader)
release(deviceWriter)

disp('Closing...')
close(tuner)