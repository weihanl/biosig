function [signal,H] = sload(FILENAME,CHAN,Fs)
% SLOAD loads signal data of various data formats
% 
% Currently are the following data formats supported: 
%    EDF, CNT, EEG, BDF, GDF, BKR, MAT(*), 
%    PhysioNet (MIT-ECG), Poly5/TMS32, SMA, RDF, CFWB,
%    Alpha-Trace, DEMG, SCP-ECG.
%
% [signal,header] = sload(FILENAME [,CHANNEL [,Fs]])
% FILENAME      name of file, or list of filenames
% channel       list of selected channels
%               default=0: loads all channels
% Fs            force target samplerate Fs (only 
%               integer and 256->100 conversion is supported) 
%
% [signal,header] = sload(dir('f*.emg'), CHAN)
% [signal,header] = sload('f*.emg', CHAN)
%  	loads channels CHAN from all files 'f*.emg'
%
% see also: SOPEN, SREAD, SCLOSE, MAT2SEL, SAVE2TXT, SAVE2BKR
%
% Reference(s):


%	$Revision: 1.33 $
%	$Id: sload.m,v 1.33 2004-09-22 11:23:53 schloegl Exp $
%	Copyright (C) 1997-2004 by Alois Schloegl 
%	a.schloegl@ieee.org	
%    	This is part of the BIOSIG-toolbox http://biosig.sf.net/

% This library is free software; you can redistribute it and/or
% modify it under the terms of the GNU Library General Public
% License as published by the Free Software Foundation; either
% Version 2 of the License, or (at your option) any later version.
%
% This library is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
% Library General Public License for more details.
%
% You should have received a copy of the GNU Library General Public
% License along with this library; if not, write to the
% Free Software Foundation, Inc., 59 Temple Place - Suite 330,
% Boston, MA  02111-1307, USA.


if nargin<2; CHAN=0; end;
if nargin<3; Fs=NaN; end;

if CHAN<1 | ~isfinite(CHAN),
        CHAN=0;
end;

if (ischar(FILENAME) & any(FILENAME=='*'))
        p = fileparts(FILENAME);
        f = dir(FILENAME);
        for k = 1:length(f);
                f(k).name = fullfile(p,f(k).name);
        end;
        FILENAME=f;
end;        

if ((iscell(FILENAME) | isstruct(FILENAME)) & (length(FILENAME)>1)),
	signal = [];
	for k = 1:length(FILENAME),
		if iscell(FILENAME(k))
			f = FILENAME{k};
		else 
			f = FILENAME(k);
		end	

		[s,h] = sload(f,CHAN,Fs);
		if k==1,
			H = h;
			signal = s;  
			LEN = size(s,1);
		else
			H.FILE(k) = h.FILE;
			if (H.SampleRate ~= h.SampleRate),
				fprintf(2,'Warning SLOAD: sampling rates of multiple files differ %i!=%i.\n',H.SampleRate, h.SampleRate);
			end;
			if size(s,2)==size(signal,2), %(H.NS == h.NS) 
				signal = [signal; repmat(NaN,100,size(s,2)); s];
			else
				fprintf(2,'ERROR SLOAD: incompatible channel numbers %i!=%i of multiple files\n',H.NS,h.NS);
				return;
			end;

                        if isfield(H,'TriggerOffset'),
                                if H.TriggerOffset ~= h.TriggerOffset,
                                        fprintf(2,'Warning SLOAD: Triggeroffset does not fit.\n',H.TriggerOffset,h.TriggerOffset);
                                        return;
                                end;
                        end;
                        if isfield(H,'Classlabel'),
                                if isfield(H,'ArtifactSelection'),
                                        H.ArtifactSelection = [H.ArtifactSelection(:);h.ArtifactSelection(:)+length(H.Classlabel)];
                                end;
                                H.Classlabel = [H.Classlabel(:);h.Classlabel(:)];
                        end;
                        if h.EVENT.N > 0,
                                H.EVENT.POS = [H.EVENT.POS; h.EVENT.POS+size(signal,1)-size(s,1)];
                                H.EVENT.TYP = [H.EVENT.TYP; h.EVENT.TYP];
                                if isfield(H.EVENT,'CHN');
                                        H.EVENT.CHN = [H.EVENT.CHN; h.EVENT.CHN];
                                end;
                                if isfield(H.EVENT,'DUR');
                                        H.EVENT.DUR = [H.EVENT.DUR; h.EVENT.DUR];
                                end;
                                H.EVENT.N   =  H.EVENT.N  + h.EVENT.N;
                        end;			
                        clear s
                end;
	end;
        ix = find(H.EVENT.TYP==hex2dec('0300')); 
        H.TRIG = mod(H.EVENT.POS(ix),256);

        
	fprintf(1,'  SLOAD: data segments are concanated with NaNs in between.\n');
	return;	
end;
%%% end of multi-file section 

%%%% start of single file section

if isstruct(FILENAME),
	HDR = FILENAME;
	if isfield(HDR,'FileName'),
    		FILENAME = HDR.FileName;
	elseif isfield(HDR,'name'),
    		FILENAME = HDR.name;
	else
    		fprintf(2,'Error SLOAD: missing FileName.\n');	
    		return; 
	end;
end;

if ~isnumeric(CHAN),
        MODE = CHAN;
        CHAN = 0; 
else
        MODE = '';
end;

signal = [];
[p,f,FileExt] = fileparts(FILENAME);
FileExt = FileExt(2:length(FileExt));
H.FileName = FILENAME;
H = sopen(H,'rb',CHAN);


if H.FILE.OPEN > 0,
        [signal,H] = sread(H);
        H = sclose(H);


elseif strcmp(H.TYPE,'EVENTCODES')
        signal = H.EVENT;


elseif strcmp(H.TYPE,'AKO')
        signal = fread(H.FILE.FID,inf,'uint8')*H.Calib(2,1)+H.Calib(1,1);
        
        fclose(H.FILE.FID);
        

elseif strcmp(H.TYPE,'DAQ')
	fprintf(1,'Loading a matlab DAQ data file - this can take a while.\n');
	tic;
        [signal, tmp, H.DAQ.T0, H.DAQ.events, DAQ.info] = daqread(H.FileName);
        fprintf(1,'Loading DAQ file finished after %.0f s.\n',toc);
        H.NS   = size(signal,2);
        
        H.SampleRate = DAQ.info.ObjInfo.SampleRate;
        sz     = size(signal);
        if length(sz)==2, sz=[1,sz]; end;
        H.NRec = sz(1);
        H.Dur  = sz(2)/H.SampleRate;
        H.NS   = sz(3);
        H.FLAG.TRIGGERED = H.NRec>1;
        H.FLAG.UCAL = 1;
        
        H.PhysDim = {DAQ.info.ObjInfo.Channel.Units};
        H.DAQ   = DAQ.info.ObjInfo.Channel;
        
        H.Cal   = diff(cat(1,DAQ.info.ObjInfo.Channel.InputRange),[],2).*(2.^(-DAQ.info.HwInfo.Bits));
        H.Off   = cat(1,DAQ.info.ObjInfo.Channel.NativeOffset); 
        H.Calib = sparse([H.Off';eye(H.NS)]*diag(H.Cal));
        
        if CHAN<1,
                CHAN = 1:H.NS; 
        end;
        if ~H.FLAG.UCAL,
                Calib = H.Calib;	% Octave can not index sparse matrices within a struct
                signal = [ones(size(signal,1),1),signal]*Calib(:,CHAN);
        end;
        
        
elseif strcmp(H.TYPE,'DIR'),
        f0 = fullfile(H.FileName,'Traindata_0.txt');
        f1 = fullfile(H.FileName,'Traindata_1.txt');
        f2 = fullfile(H.FileName,'Testdata.txt');
        
        if exist(f0,'file') & exist(f1,'file') & exist(f2,'file')
                % BCI competition 2003, dataset 1a+b (Tuebingen)
                data = load('-ascii', f0);
                test = load('-ascii', f1);
                data = [data; test];
                test = load('-ascii',f2);
                H.Classlabel = [data(:,1); repmat(NaN,size(test,1),1)];

                H.NRec = length(H.Classlabel);
                H.FLAG.TRIGGERED = H.NRec>1; 
                H.PhysDim = '�V';
                H.SampleRate = 256; 
                
                if strcmp(H.FILE.Name,'a34lkt') 
                        H.INFO='BCI competition 2003, dataset 1a (Tuebingen)';
                        H.Dur = 3.5; 
                        H.Label = {'A1-Cz';'A2-Cz';'C3f';'C3p';'C4f';'C4p'};
                        H.TriggerOffset = -2; %[s]
                end;
                
                if strcmp(H.FILE.Name,'egl2ln')
                        H.INFO='BCI competition 2003, dataset 1b (Tuebingen)';
                        H.Dur = 4.5; 
                        H.Label = {'A1-Cz';'A2-Cz';'C3f';'C3p';'vEOG';'C4f';'C4p'};
                        H.TriggerOffset = -2; %[s]
                end;
                H.SPR = H.SampleRate*H.Dur;
                H.NS  = length(H.Label);
                signal= reshape(permute(reshape([data(:,2:H.SPR*H.NS+1);test], [H.NRec, H.SPR, H.NS]),[2,1,3]),[H.SPR*H.NRec,H.NS]);
        end;
        
        
elseif strncmp(H.TYPE,'MAT',3),
        tmp = load('-MAT',FILENAME);
        if isfield(tmp,'y'),		% Guger, Mueller, Scherer
                H.NS = size(tmp.y,2);
                if ~isfield(tmp,'SampleRate')
                        %fprintf(H.FILE.stderr,['Samplerate not known in ',FILENAME,'. 125Hz is chosen']);
                        H.SampleRate=125;
                else
                        H.SampleRate=tmp.SampleRate;
                end;
                fprintf(H.FILE.stderr,'Sensitivity not known in %s.\n',FILENAME);
                if any(CHAN),
                        signal = tmp.y(:,CHAN);
                else
        	        signal = tmp.y;
                end;
                
                
        elseif isfield(tmp,'run') & isfield(tmp,'trial') & isfield(tmp,'sample') & isfield(tmp,'signal') & isfield(tmp,'TargetCode');
                H.INFO='BCI competition 2003, dataset 2a (Albany)'; 
                H.SampleRate = 160; 
                if CHAN>0,
                        signal = tmp.signal(:,CHAN); 
                else
                        signal = tmp.signal; 
                end
                H.EVENT.POS = [0;find(diff(tmp.trial)>0)-1];
                H.EVENT.TYP = ones(length(H.EVENT.POS),1)*hex2dec('0300'); % trial onset; 
                
                if 0,
                        EVENT.POS = [find(diff(tmp.trial)>0);length(tmp.trial)];
                        EVENT.TYP = ones(length(EVENT.POS),1)*hex2dec('8300'); % trial offset; 
                        H.EVENT.POS = [H.EVENT.POS; EVENT.POS];
                        H.EVENT.TYP = [H.EVENT.TYP; EVENT.TYP];
                        [H.EVENT.POS,ix]=sort(H.EVENT.POS);
                        H.EVENT.TYP = H.EVENT.TYP(ix);
                end;
                
                H.EVENT.N = length(H.EVENT.POS);
                ix = find((tmp.TargetCode(1:end-1)==0) & (tmp.TargetCode(2:end)>0));
                H.Classlabel = tmp.TargetCode(ix+1); 
                
                
        elseif isfield(tmp,'runnr') & isfield(tmp,'trialnr') & isfield(tmp,'samplenr') & isfield(tmp,'signal') & isfield(tmp,'StimulusCode');
                H.INFO='BCI competition 2003, dataset 2b (Albany)'; 
                H.SampleRate = 240; 
                if CHAN>0,
                        signal = tmp.signal(:,CHAN); 
                else
                        signal = tmp.signal; 
                end
                H.EVENT.POS = [0;find(diff(tmp.trialnr)>0)-1];
                H.EVENT.TYP = ones(length(H.EVENT.POS),1)*hex2dec('0300'); % trial onset; 

                if 0,
                        EVENT.POS = [find(diff(tmp.trial)>0);length(tmp.trial)];
                        EVENT.TYP = ones(length(EVENT.POS),1)*hex2dec('8300'); % trial offset; 
                        H.EVENT.POS = [H.EVENT.POS; EVENT.POS];
                        H.EVENT.TYP = [H.EVENT.TYP; EVENT.TYP];
                        [H.EVENT.POS,ix]=sort(H.EVENT.POS);
                        H.EVENT.TYP = H.EVENT.TYP(ix);
                end;
                
                H.EVENT.N = length(H.EVENT.POS);
                ix = find((tmp.StimulusCode(1:end-1)==0) & (tmp.StimulusCode(2:end)>0));
                H.Classlabel = tmp.StimulusCode(ix+1); 
                
                
        elseif isfield(tmp,'x_train') & isfield(tmp,'y_train') & isfield(tmp,'x_test');	
                H.INFO='BCI competition 2003, dataset 3 (Graz)'; 
                H.Label = {'C3','Cz','C4'};

                H.SampleRate = 128; 
                H.Classlabel = [tmp.y_train-1;repmat(nan,size(tmp.x_test,3),1)];
                signal = cat(3,tmp.x_test,tmp.x_train);
                
                H.NRec = length(H.Classlabel);
                H.FLAG.TRIGGERED = 1; 
                H.SampleRate = 128;
                H.Dur = 9; 
                H.NS  = 3;
                H.SPR = H.SampleRate*H.Dur;
                
                sz = [H.NS,H.SPR,H.NRec];
                signal=reshape(permute(signal,[2,1,3]),sz(1),sz(2)*sz(3))';
                
                
        elseif isfield(tmp,'clab') & isfield(tmp,'x_train') & isfield(tmp,'y_train') & isfield(tmp,'x_test');	
                H.INFO='BCI competition 2003, dataset 4 (Berlin)'; 
                %load('berlin/sp1s_aa_1000Hz.mat');
                H.Classlabel=[repmat(nan,size(tmp.x_test,3),1);tmp.y_train';repmat(nan,size(tmp.x_test,3),1)];
                H.NRec = length(H.Classlabel);
                
                H.SampleRate = 1000;
                H.Dur = 0.5; 
                H.NS  = size(tmp.x_test,2);
                H.SPR = H.SampleRate*H.Dur;
                H.FLAG.TRIGGERED = 1; 
                sz = [H.NS,H.SPR,H.NRec];
                
                signal = reshape(permute(cat(3,tmp.x_test,tmp.x_train,tmp.x_test),[2,1,3]),sz(1),sz(2)*sz(3))';
                
                
        elseif isfield(tmp,'RAW_SIGNALS')    % TFM Matlab export 
                H.Label = fieldnames(tmp.RAW_SIGNALS);
                H.SampleRate = 1000; 
                H.TFM.SampleRate = 1000./[10,20,5,1,2];
                signal = [];
                for k1 = 4;1:length(H.Label);
                        s = getfield(tmp.RAW_SIGNALS,H.Label{k1});
                        ix = [];
                        for k2 = 1:length(s);
                                ix = [ix;length(s{k2})];   
                        end;
                        H.EVENT.POS(:,k1) = cumsum(ix);
                        signal = cat(1,s{k1})';
                end;

                
        elseif isfield(tmp,'daten');	% Woertz, GLBMT-Uebungen 2003
                H = tmp.daten;
                signal = H.raw*H.Cal;
                
                
        elseif isfield(tmp,'eeg');	% Scherer
                fprintf(H.FILE.stderr,'Warning SLOAD: Sensitivity not known in %s,\n',FILENAME);
                H.NS=size(tmp.eeg,2);
                if ~isfield(tmp,'SampleRate')
                        %fprintf(H.FILE.stderr,['Samplerate not known in ',FILENAME,'. 125Hz is chosen']);
                        H.SampleRate=125;
                else
                        H.SampleRate=tmp.SampleRate;
                end;
                if any(CHAN),
                        signal = tmp.eeg(:,CHAN);
                else
        	        signal = tmp.eeg;
                end;
                if isfield(tmp,'classlabel'),
                	H.Classlabel = tmp.classlabel;
                end;        

                
        elseif isfield(tmp,'P_C_S');	% G.Tec Ver 1.02, 1.5x data format
                if isa(tmp.P_C_S,'data'), %isfield(tmp.P_C_S,'version'); % without BS.analyze	
                        if any(tmp.P_C_S.Version==[1.02, 1.5, 1.52]),
                        else
                                fprintf(H.FILE.stderr,'Warning: PCS-Version is %4.2f.\n',tmp.P_C_S.Version);
                        end;
                        H.Filter.LowPass  = tmp.P_C_S.LowPass;
                        H.Filter.HighPass = tmp.P_C_S.HighPass;
                        H.Filter.Notch    = tmp.P_C_S.Notch;
                        H.SampleRate      = tmp.P_C_S.SamplingFrequency;
                        H.gBS.Attribute   = tmp.P_C_S.Attribute;
                        H.gBS.AttributeName = tmp.P_C_S.AttributeName;
                        H.Label = tmp.P_C_S.ChannelName;
                        H.gBS.EpochingSelect = tmp.P_C_S.EpochingSelect;
                        H.gBS.EpochingName = tmp.P_C_S.EpochingName;

                        signal = double(tmp.P_C_S.Data);
                        
                else %if isfield(tmp.P_C_S,'Version'),	% with BS.analyze software, ML6.5
                        if any(tmp.P_C_S.version==[1.02, 1.5, 1.52]),
                        else
                                fprintf(H.FILE.stderr,'Warning: PCS-Version is %4.2f.\n',tmp.P_C_S.version);
                        end;        
                        H.Filter.LowPass  = tmp.P_C_S.lowpass;
                        H.Filter.HighPass = tmp.P_C_S.highpass;
                        H.Filter.Notch    = tmp.P_C_S.notch;
                        H.SampleRate      = tmp.P_C_S.samplingfrequency;
                        H.gBS.Attribute   = tmp.P_C_S.attribute;
                        H.gBS.AttributeName = tmp.P_C_S.attributename;
                        H.Label = tmp.P_C_S.channelname;
                        H.gBS.EpochingSelect = tmp.P_C_S.epochingselect;
                        H.gBS.EpochingName = tmp.P_C_S.epochingname;
                        
                        signal = double(tmp.P_C_S.data);
                end;
                tmp = []; % clear memory

                sz     = size(signal);
                H.NRec = sz(1);
                H.Dur  = sz(2)/H.SampleRate;
                H.NS   = sz(3);
                H.FLAG.TRIGGERED = H.NRec>1;
                
                if any(CHAN),
                        %signal = signal(:,CHAN);
                        sz(3)= length(CHAN);
                else
                        CHAN = 1:H.NS;
                end;
                signal = reshape(permute(signal(:,:,CHAN),[2,1,3]),[sz(1)*sz(2),sz(3)]);

                % Selection of trials with artifacts
                ch = strmatch('ARTIFACT',H.gBS.AttributeName);
                if ~isempty(ch)
                        H.ArtifactSelection = H.gBS.Attribute(ch,:);
                end;
                
                % Convert gBS-epochings into BIOSIG - Events
                map = zeros(size(H.gBS.EpochingName,1),1);
                map(strmatch('AUGE',H.gBS.EpochingName))=hex2dec('0101');
                map(strmatch('EOG',H.gBS.EpochingName))=hex2dec('0101');
                map(strmatch('MUSKEL',H.gBS.EpochingName))=hex2dec('0103');
                map(strmatch('MUSCLE',H.gBS.EpochingName))=hex2dec('0103');
                map(strmatch('ELECTRODE',H.gBS.EpochingName))=hex2dec('0105');

                if ~isempty(H.gBS.EpochingSelect),
                        H.EVENT.TYP = map([H.gBS.EpochingSelect{:,9}]');
                        H.EVENT.POS = [H.gBS.EpochingSelect{:,1}]';
                        H.EVENT.CHN = [H.gBS.EpochingSelect{:,3}]';
                        H.EVENT.DUR = [H.gBS.EpochingSelect{:,4}]';
                end;
                
	elseif isfield(tmp,'P_C_DAQ_S');
                if ~isempty(tmp.P_C_DAQ_S.data),
                        signal = double(tmp.P_C_DAQ_S.data{1});
                        
                elseif ~isempty(tmp.P_C_DAQ_S.daqboard),
                        [tmppfad,file,ext] = fileparts(tmp.P_C_DAQ_S.daqboard{1}.ObjInfo.LogFileName),
                        file = [file,ext];
                        if exist(file,'file')
                                signal=daqread(file);        
                                H.info=daqread(file,'info');        
                        else
                                fprintf(H.FILE.stderr,'Error SLOAD: no data file found\n');
                                return;
                        end;
                        
                else
                        fprintf(H.FILE.stderr,'Error SLOAD: no data file found\n');
                        return;
                end;
                
                H.NS = size(signal,2);
                %scale  = tmp.P_C_DAQ_S.sens;      
                H.Cal = tmp.P_C_DAQ_S.sens*(2.^(1-tmp.P_C_DAQ_S.daqboard{1}.HwInfo.Bits));
                
                if all(tmp.P_C_DAQ_S.unit==1)
                        H.PhysDim='uV';
                else
                        H.PhysDim='[?]';
                end;
                
                H.SampleRate = tmp.P_C_DAQ_S.samplingfrequency;
                sz     = size(signal);
                if length(sz)==2, sz=[1,sz]; end;
                H.NRec = sz(1);
                H.Dur  = sz(2)/H.SampleRate;
                H.NS   = sz(3);
                H.FLAG.TRIGGERED = H.NRec>1;
                H.Filter.LowPass = tmp.P_C_DAQ_S.lowpass;
                H.Filter.HighPass = tmp.P_C_DAQ_S.highpass;
                H.Filter.Notch = tmp.P_C_DAQ_S.notch;
                if any(CHAN),
                        signal=signal(:,CHAN);
                else
                        CHAN=1:H.NS;
                end; 
                if ~H.FLAG.UCAL,
			signal=signal*diag(H.Cal(CHAN));                	        
                end;
                
        elseif isfield(tmp,'data');	% Mueller, Scherer ? 
                H.NS = size(tmp.data,2);
                fprintf(H.FILE.stderr,'Warning SLOAD: Sensitivity not known in %s,\n',FILENAME);
                if ~isfield(tmp,'SampleRate')
                        fprintf(H.FILE.stderr,'Warning SLOAD: Samplerate not known in %s. 125Hz is chosen\n',FILENAME);
                        H.SampleRate=125;
                else
                        H.SampleRate=tmp.SampleRate;
                end;
                if any(CHAN),
                        signal = tmp.data(:,CHAN);
                else
        	        signal = tmp.data;
                end;
                if isfield(tmp,'classlabel'),
                	H.Classlabel = tmp.classlabel;
                end;        
                if isfield(tmp,'artifact'),
                	H.ArtifactSelection = zeros(size(tmp.classlabel));
                        H.ArtifactSelection(tmp.artifact)=1;
                end;        
                
        elseif isfield(tmp,'EEGdata');  % Telemonitoring Daten (Reinhold Scherer)
                H.NS = size(tmp.EEGdata,2);
                H.Classlabel = tmp.classlabel;
                if ~isfield(tmp,'SampleRate')
                        fprintf(H.FILE.stderr,'Warning SLOAD: Samplerate not known in %s. 125Hz is chosen\n',FILENAME);
                        H.SampleRate=125;
                else
                        H.SampleRate=tmp.SampleRate;
                end;
                H.PhysDim = '�V';
                fprintf(H.FILE.stderr,'Sensitivity not known in %s. 50�V is chosen\n',FILENAME);
                if any(CHAN),
                        signal = tmp.EEGdata(:,CHAN)*50;
                else
                        signal = tmp.EEGdata*50;
                end;
                

        elseif isfield(tmp,'daten');	% EP Daten von Michael Woertz
                H.NS = size(tmp.daten.raw,2)-1;
                if ~isfield(tmp,'SampleRate')
                        fprintf(H.FILE.stderr,'Warning SLOAD: Samplerate not known in %s. 2000Hz is chosen\n',FILENAME);
                        H.SampleRate=2000;
                else
                        H.SampleRate=tmp.SampleRate;
                end;
                H.PhysDim = '�V';
                fprintf(H.FILE.stderr,'Sensitivity not known in %s. 100�V is chosen\n',FILENAME);
                %signal=tmp.daten.raw(:,1:H.NS)*100;
                if any(CHAN),
                        signal = tmp.daten.raw(:,CHAN)*100;
                else
                        signal = tmp.daten.raw*100;
                end;
                
        elseif isfield(tmp,'neun') & isfield(tmp,'zehn') & isfield(tmp,'trig');	% guger, 
                H.NS=3;
                if ~isfield(tmp,'SampleRate')
                        fprintf(H.FILE.stderr,'Warning SLOAD: Samplerate not known in %s. 125Hz is chosen\n',FILENAME);
                        H.SampleRate=125;
                else
                        H.SampleRate=tmp.SampleRate;
                end;
                fprintf(H.FILE.stderr,'Sensitivity not known in %s. \n',FILENAME);
                signal  = [tmp.neun;tmp.zehn;tmp.trig];
                H.Label = {'Neun','Zehn','TRIG'};
                if any(CHAN),
                        signal=signal(:,CHAN);
                end;        
                
                
        elseif isfield(tmp,'header')    % Scherer
                signal =[];
                H = tmp.header;

                
        elseif isfield(tmp,'Recorder1')    % Nicolet NRF format converted into Matlab 
                for k = 1:length(s.Recorder1.Channels.ChannelInfos);
                        H.Label{k} = s.Recorder1.Channels.ChannelInfos(k).ChannelInfo.Name;
                        H.PhysDim{k} = s.Recorder1.Channels.ChannelInfos(k).ChannelInfo.YUnits;
                end;
                signal = [];
                T = [];
                for k = 1:length(s.Recorder1.Channels.Segments)
                        tmp = s.Recorder1.Channels.Segments(k).Data;
                        sz = size(tmp.Samples);
                        signal = [signal; repmat(nan,100,sz(1)); tmp.Samples'];
                        T = [T;repmat(nan,100,1);tmp.dX0+(1:sz(2))'*tmp.dXstep ]
                        fs = 1./tmp.dXstep;
                        if k==1,
                                H.SampleRate = fs;
                        elseif H.SampleRate ~= fs; 
                                fprintf(2,'Error SLOAD (NRF): different Sampling rates not supported, yet.\n');
                        end;
                end;
                
        else
		signal = [];
                fprintf(H.FILE.stderr,'Warning SLOAD: MAT-file %s not identified as BIOSIG signal\n',FILENAME);
                whos('-file',FILENAME);
        end;        

        
elseif strcmp(H.TYPE,'BIFF'),
	try, 
                [H.TFM.S,H.TFM.E] = xlsread(H.FileName,'Beat-To-Beat');
                if size(H.TFM.S,1)+1==size(H.TFM.E,1),
                        H.TFM.S = [repmat(NaN,1,size(H.TFM.S,2));H.TFM.S];
                end;

                H.TYPE = 'TFM_EXCEL_Beat_to_Beat'; 
                if ~isempty(findstr(H.TFM.E{3,1},'---'))
                        H.TFM.S(3,:) = [];    
                        H.TFM.E(3,:) = [];    
                end;
                
                H.Label   = H.TFM.E(4,:)';
                H.PhysDim = H.TFM.E(5,:)';
           
                H.TFM.S = H.TFM.S(6:end,:);
                H.TFM.E = H.TFM.E(6:end,:);
                
                ix = find(isnan(H.TFM.S(:,2)) & ~isnan(H.TFM.S(:,1)));
                
                H.EVENT.Desc = H.TFM.E(ix,2);
                H.EVENT.POS  = ix;
                
                S(:,3) = S(:,3)/1000;   % convert RRI from [ms] into [s]
                H.PhysDim{3} = '[s]';

                if ~CHAN,
			signal  = H.TFM.S;
		else
			signal  = H.TFM.S(:,CHAN);
		end;
	catch,

        end;


elseif strcmp(H.TYPE,'BMP'),
                H.FILE.FID = fopen(H.FileName,'rb','ieee-le');
		fseek(H.FILE.FID,10,-1);

		tmp = fread(H.FILE.FID,4,'uint32');
		H.HeadLen = tmp(1);
		H.BMP.sizeBitmapInfoHeader = tmp(2);
		H.BMP.Size = tmp(3:4)';

		tmp = fread(H.FILE.FID,2,'uint16');
		H.BMP.biPlanes = tmp(1);
		H.bits = tmp(2);

		tmp = fread(H.FILE.FID,6,'uint32');
		H.BMP.biCompression = tmp(1);
		H.BMP.biImageSize = tmp(2);
		H.BMP.biXPelsPerMeter = tmp(3);
		H.BMP.biYPelsPerMeter = tmp(4);
		H.BMP.biColorUsed = tmp(5);
		H.BMP.biColorImportant = tmp(6);
		
		fseek(H.FILE.FID,H.HeadLen,'bof');
		nc = ceil((H.bits*H.BMP.Size(1))/32)*4;

		if (H.bits==1)
			signal = fread(H.FILE.FID,[nc,H.BMP.Size(2)*8],'ubit1');
			signal = signal(1:H.BMP.Size(1),:)';

		elseif (H.bits==4)
			palr   = [  0,128,  0,128,  0,128,  0,192,128,255,  0,255,  0,255,  0,255]; 
			palg   = [  0,  0,128,128,  0,  0,128,192,128,  0,255,255,  0,  0,255,255]; 
			palb   = [  0,  0,  0,  0,128,128,128,192,128,  0,  0,  0,255,255,255,255]; 
			tmp    = uint8(fread(H.FILE.FID,[nc,H.BMP.Size(2)*2],'ubit4'));
			signal        = palr(tmp(1:H.BMP.Size(1),:)'+1);
			signal(:,:,2) = palg(tmp(1:H.BMP.Size(1),:)'+1);
			signal(:,:,3) = palb(tmp(1:H.BMP.Size(1),:)'+1);
	    		signal = signal(H.BMP.Size(2):-1:1,:,:);

		elseif (H.bits==8)
			pal = uint8(colormap*256);
			tmp = fread(H.FILE.FID,[nc,H.BMP.Size(2)],'uint8');
			signal        = pal(tmp(1:H.BMP.Size(1),:)'+1,1);
			signal(:,:,2) = pal(tmp(1:H.BMP.Size(1),:)'+1,2);
			signal(:,:,3) = pal(tmp(1:H.BMP.Size(1),:)'+1,3);
	    		signal = signal(H.BMP.Size(2):-1:1,:,:);

		elseif (H.bits==24)
			[signal]    = uint8(fread(H.FILE.FID,[nc,H.BMP.Size(2)],'uint8'));
			H.BMP.Red   = signal((1:H.BMP.Size(1))*3,:)';
			H.BMP.Green = signal((1:H.BMP.Size(1))*3-1,:)';
			H.BMP.Blue  = signal((1:H.BMP.Size(1))*3-2,:)';
			signal = H.BMP.Red;
			signal(:,:,2) = H.BMP.Green;
			signal(:,:,3) = H.BMP.Blue;
	    		signal = signal(H.BMP.Size(2):-1:1,:,:);
		else

		end;
                fclose(H.FILE.FID);

        
elseif strcmp(H.TYPE,'unknown')
        TYPE = upper(H.FILE.Ext);
        if strcmp(TYPE,'DAT')
                loaddat;     
                signal = Voltage(:,CHAN);
        elseif strcmp(TYPE,'RAW')
                loadraw;
        elseif strcmp(TYPE,'RDT')
                [signal] = loadrdt(FILENAME,CHAN);
                fs = 128;
        elseif strcmp(TYPE,'XLS')
                loadxls;
        elseif strcmp(TYPE,'DA_')
                fprintf('Warning SLOAD: Format DA# in testing state and is not supported\n');
                loadda_;
        elseif strcmp(TYPE,'RG64')
                [signal,H.SampleRate,H.Label,H.PhysDim,H.NS]=loadrg64(FILENAME,CHAN);
                %loadrg64;
        else
                fprintf('Error SLOAD: Unknown Data Format\n');
                signal = [];
        end;
        
        
end;


if strcmp(H.TYPE,'CNT');    
        f = fullfile(H.FILE.Path, [H.FILE.Name,'.txt']); 
        if exist(f,'file'),
                fid = fopen(f,'r');
		tmp = fread(fid,inf,'char');
		fclose(fid);
		[tmp,v] = str2double(char(tmp'));
		if ~any(v), 
            		H.Classlabel=tmp(:);                        
	        end;
        end
        f = fullfile(H.FILE.Path, [H.FILE.Name,'.mat']);
        if exist(f,'file'),
                tmp = load(f);
                if isfield(tmp,'classlabel') & ~isfield(H,'Classlabel')
                        H.Classlabel=tmp.classlabel(:);                        
                elseif isfield(tmp,'classlabel') & isfield(tmp,'header') & isfield(tmp.header,'iniFile') & strcmp(tmp.header.iniFile,'oom.ini'), %%% for OOM study only. 
                        H.Classlabel=tmp.classlabel(:);                        
                end;
        end;
        f = fullfile(H.FILE.Path, [H.FILE.Name,'c.mat']);
        if exist(f,'file'),
                tmp = load(f);
                if isfield(tmp,'classlabel') & ~isfield(H,'Classlabel')
                        H.Classlabel=tmp.classlabel(:);                        
                end;
        end;
end;

if ~isempty(findstr(upper(MODE),'TSD'));
        f = fullfile(H.FILE.Path, [H.FILE.Name,'.tsd']);
        if ~exist(f,'file'),
                        fprintf(2,'Warning SLOAD-TSD: file %s.tsd found\n',H.FILE(1).Name,H.FILE(1).Name);
        else
                fid = fopen(f,'rb');
                tsd = fread(fid,inf,'float');
                fclose(fid);
                nc = size(signal,1)\size(tsd,1);
                if (nc == round(nc)),
                        signal = [signal, reshape(tsd,nc,size(tsd,1)/nc)'];
                else
                        fprintf(2,'Warning SLOAD: size of %s.tsd does not fit to size of %s.bkr\n',H.FILE(1).Name,H.FILE(1).Name);
                end;
        end;
end;

%%%%% if possible, load Reinhold's configuration files
if any(strmatch(H.TYPE,{'BKR','GDF'}));
        f = fullfile(H.FILE.Path, [H.FILE.Name,'.mat']);
        if exist(f,'file'),
                x = load(f,'header');
		if isfield(x,'header'),
	                H.BCI.Paradigm = x.header.Paradigm;
    		        if isfield(H.BCI.Paradigm,'TriggerTiming');
    		                H.TriggerOffset = H.BCI.Paradigm.TriggerTiming;
            		elseif isfield(H.BCI.Paradigm,'TriggerOnset');
                    		H.TriggerOffset = H.BCI.Paradigm.TriggerOnset;
            		end;
                        
                        if isempty(H.Classlabel),
                                H.Classlabel = x.header.Paradigm.Classlabel;
                        end;
		end;
        end;
end;

% resampling 
if ~isnan(Fs) & (H.SampleRate~=Fs);
        tmp = ~mod(H.SampleRate,Fs) | ~mod(Fs,H.SampleRate);
        tmp2= ~mod(H.SampleRate,Fs*2.56);
        if tmp,
                signal = rs(signal,H.SampleRate,Fs);
                H.EVENT.POS = H.EVENT.POS/H.SampleRate*Fs;
                if isfield(H.EVENT,'DUR');
                        H.EVENT.DUR = H.EVENT.DUR/H.SampleRate*Fs;
                end;
                H.SampleRate = Fs;
        elseif tmp2,
                x = load('resample_matrix.mat');
                signal = rs(signal,x.T256100);
                if H.SampleRate*100~=Fs*256,
                        signal = rs(signal,H.SampleRate/(Fs*2.56),1);
                end;
                H.EVENT.POS = H.EVENT.POS/H.SampleRate*Fs;
                if isfield(H.EVENT,'DUR');
                        H.EVENT.DUR = H.EVENT.DUR/H.SampleRate*Fs;
                end;
                H.SampleRate = Fs;
        else 
                fprintf(2,'Warning SLOAD: resampling %f Hz to %f Hz not implemented.\n',H.SampleRate,Fs);
        end;                
end;

