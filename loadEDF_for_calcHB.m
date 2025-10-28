function [SpO2, RespEvents, SleepStage] = loadEDF_for_calcHB(edfFilename)
% Beolvas egy EDF fájlt (amely TIMETABLE-ként töltődik be) és
% átalakítja a calcHB függvény által várt formátumra.
%
% VERZIÓ 2.0 - Timetable-alapú EDFread-hez igazítva

fprintf('EDF fájl beolvasása (Timetable mód): %s\n', edfFilename);
try
    % 1. LÉPÉS: Az EDF beolvasása timetable-ként
    % Ez a hívás csak egyetlen változót ad vissza.
    data_timetable = edfread(edfFilename); 
catch ME
    fprintf('Hiba az edfread futtatása közben.\n');
    fprintf('Győződjön meg róla, hogy a Signal Processing Toolbox telepítve van.\n');
    error('edfread hiba: %s', ME.message);
end

fprintf('  Timetable beolvasva. Jelek és SR-ek kinyerése...\n');

% 2. LÉPÉS: A Timetable átalakítása a szkript által várt formátumra
% (signalCell és signalHeader)

all_labels = data_timetable.Properties.VariableNames;
time_step_duration = seconds(data_timetable.Properties.TimeStep); % pl. 60 másodperc

signalHeader.Labels = {};
signalHeader.SampleRates = [];
signalCell = {};

for i = 1:length(all_labels)
    label_raw = all_labels{i};
    
    % Kihagyjuk az időoszlopot
    if strcmpi(label_raw, 'Record Time')
        continue;
    end
    
    % "Tiszta" címke kinyerése (pl. "SignalLabel5_Saturation" -> "Saturation")
    underscore_idx = strfind(label_raw, '_');
    if isempty(underscore_idx)
        label_clean = label_raw;
    else
        % Vegyük az első aláhúzás utáni részt
        label_clean = label_raw(underscore_idx(1)+1 : end);
    end
    
    % A teljes jel rekonstruálása a blokkokból
    % A data_timetable.(label_raw) egy cellatömb, tele {60x1 double} blokkokkal
    signal_blocks = data_timetable.(label_raw);
    full_signal = vertcat(signal_blocks{:}); % Összefűzzük az összes blokkot
    
    % Mintavételi frekvencia (SR) kinyerése
    % SR = (minták száma egy blokkban) / (blokk időtartama)
    num_samples_in_block = length(signal_blocks{1});
    sr = num_samples_in_block / time_step_duration;
    
    % Eltároljuk a kinyert adatokat a várt struktúrákba
    signalHeader.Labels{end+1} = label_clean;
    signalHeader.SampleRates(end+1) = sr;
    signalCell{end+1} = full_signal;
    
    % fprintf('    -> Kinyerve: %s (SR = %.1f Hz)\n', label_clean, sr);
end

fprintf('  Adatok sikeresen átalakítva.\n');

%% 1. SpO2 csatorna kinyerése (INNENTŐL A KÓD VÁLTOZATLAN)
fprintf('=== SpO2 feldolgozása ===\n');

% Keressük az SpO2 csatornát
% Az Ön kimenete: "SignalLabel5_Saturation" -> "Saturation"
spo2Idx = find(contains(signalHeader.Labels, 'Saturation', 'IgnoreCase', true) | ...
               contains(signalHeader.Labels, 'SpO2', 'IgnoreCase', true));
           
if isempty(spo2Idx)
    error('Nem található "Saturation" vagy "SpO2" csatorna az EDF fájlban.');
end
spo2Idx = spo2Idx(1); % Az első találatot használjuk

SpO2.Sig = signalCell{spo2Idx};
SpO2.SR = signalHeader.SampleRates(spo2Idx);

fprintf('  Csatorna: %s\n', signalHeader.Labels{spo2Idx});
fprintf('  Mintavétel: %d Hz\n', SpO2.SR);

% A calcHB 1 Hz-et vár! Ha nem annyi, átalakítjuk.
if SpO2.SR ~= 1
    fprintf('  FIGYELEM: Az SpO2 csatorna %d Hz. Átmintavételezés 1 Hz-re...\n', SpO2.SR);
    SpO2.Sig = resample(SpO2.Sig, 1, SpO2.SR);
    SpO2.SR = 1;
    fprintf('  Új jelszám: %d\n', length(SpO2.Sig));
end

%% 2. RespEvents (Légzési események) feldolgozása
fprintf('=== Légzési események (RespEvents) feldolgozása ===\n');

% Definiáljuk, mit keresünk és mire képezzük le
% Az Ön kimenetei: "SignalLabel28_Hypopnea", "SignalLabel8_ObstructiveApne", "SignalLabel9_CentralApnea"
channelMap = struct(...
    'EDF_Name', {'Hypopnea', 'ObstructiveApne', 'CentralApne'}, ...
    'HB_Type', {'H', 'OA', 'C'} ...
);

RespEvents.Type = {};
RespEvents.Start = [];
RespEvents.Duration = [];

for i = 1:length(channelMap)
    targetName = channelMap(i).EDF_Name;
    eventType = channelMap(i).HB_Type;
    
    % Csatorna keresése (részleges egyezéssel, kis/nagybetű érzéketlenül)
    % A 'contains' miatt az "ObstructiveApne" illeszkedni fog az "Obstructive apne"-ra
    eventIdx = find(contains(signalHeader.Labels, targetName, 'IgnoreCase', true));
    
    if isempty(eventIdx)
        fprintf('  FIGYELEM: "%s" csatorna nem található, kihagyva.\n', targetName);
        continue;
    end
    
    eventIdx = eventIdx(1);
    sig = signalCell{eventIdx};
    sr = signalHeader.SampleRates(eventIdx);
    fprintf('  Feldolgozás: "%s" (%d Hz) -> %s típus\n', signalHeader.Labels{eventIdx}, sr, eventType);

    % Esemény detektálás:
    eventMask = sig > 0;
    
    eventStarts_samples = find(diff([0; eventMask]) == 1);
    eventEnds_samples = find(diff([eventMask; 0]) == -1);
    
    if length(eventStarts_samples) ~= length(eventEnds_samples)
        fprintf('    Hiba: Az esemény kezdetek/végek száma nem egyezik. Vágás...\n');
        minLen = min(length(eventStarts_samples), length(eventEnds_samples));
        eventStarts_samples = eventStarts_samples(1:minLen);
        eventEnds_samples = eventEnds_samples(1:minLen);
    end
    
    numEventsFound = length(eventStarts_samples);
    if numEventsFound == 0
        fprintf('    Nincs detektálható %s esemény.\n', eventType);
        continue;
    end

    starts_sec = (eventStarts_samples - 1) / sr; 
    durations_samples = (eventEnds_samples - eventStarts_samples) + 1;
    durations_sec = durations_samples / sr;
    
    RespEvents.Type = [RespEvents.Type, repmat({eventType}, 1, numEventsFound)];
    RespEvents.Start = [RespEvents.Start, starts_sec'];
    RespEvents.Duration = [RespEvents.Duration, durations_sec'];
    
    fprintf('    %d db %s esemény detektálva.\n', numEventsFound, eventType);
end

if ~isempty(RespEvents.Start)
    [RespEvents.Start, sortIdx] = sort(RespEvents.Start);
    RespEvents.Type = RespEvents.Type(sortIdx);
    RespEvents.Duration = RespEvents.Duration(sortIdx);
    fprintf('  Összesen %d esemény, időrendbe rendezve.\n', length(RespEvents.Start));
else
    fprintf('  NEM TALÁLHATÓ EGYIK LÉGZÉSI ESEMÉNY CSATORNA SEM.\n');
end


%% 3. SleepStage (Alvási stádium) generálása
fprintf('=== Alvási stádium (SleepStage) generálása ===\n');

len = length(SpO2.Sig); % Hossz az 1 Hz-es SpO2 jelből

SleepStage.Annotation = 2 * ones(1, len); % Vektor, tele 2-esekkel
SleepStage.Codes = [0 1 2 3 4 5 9];
SleepStage.Description = {'Wake','Stage 1','Stage 2','Stage 3','Stage 4','REM','Indeterminant'};
SleepStage.SR = 1; % 1 Hz, ahogy a calcHB várja!

fprintf('  Generálva: %d pont, mind "Stage 2".\n', len);
fprintf('  Mintavétel: %d Hz.\n', SleepStage.SR);

fprintf('\n=== Adatfeldolgozás kész ===\n');

end