% 1. Adatok betöltése és átalakítása az EDF fájlból. EDF+ fájl nem
% használható ennél a verziónál
edfFajlNeve = 'Angyal_2024-01-31.EDF';
[SpO2, RespEvents, SleepStage] = loadEDF_for_calcHB(edfFajlNeve);

% 2. Hypoxic Burden számítás futtatása a betöltött adatokkal
% (Győződjön meg róla, hogy a calcHB.m is az elérési útvonalon van)
fprintf('\n=== Hypoxic Burden Számítás (calcHB) indítása ===\n');
HB = calcHB(SpO2, RespEvents, SleepStage, true); % true = legyen ábra

fprintf('============================================\n');
fprintf('Eredmény: Hypoxic Burden (HB) = %.2f %%min/óra\n', HB);
fprintf('============================================\n');