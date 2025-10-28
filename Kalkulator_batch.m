%% Kalkulator_Batch.m

% 1. LÉPÉS: Összegyűjtjük a mappában lévő összes .EDF fájlt
fileList = dir('*.EDF');

if isempty(fileList)
    error('Nem található .EDF fájl az aktuális mappában!');
end

% Előkészítjük az eredmények tárolására szolgáló cellatömböt
% (Oszlopok: Fájlnév, HB Érték)
results = cell(length(fileList), 2); 

fprintf('=== %d db EDF fájl feldolgozása elkezdődött ===\n', length(fileList));

% 2. LÉPÉS: Végigmegyünk minden fájlon
for i = 1:length(fileList)
    edfFajlNeve = fileList(i).name;
    
    fprintf('\n----------------------------------------\n');
    fprintf('Fájl feldolgozása (%d/%d): %s\n', i, length(fileList), edfFajlNeve);
    fprintf('----------------------------------------\n');
    
    try
        % 3. LÉPÉS: Beolvassuk az adatokat
        [SpO2, RespEvents, SleepStage] = loadEDF_for_calcHB(edfFajlNeve);
        
        % 4. LÉPÉS: HB érték kiszámítása
        % ITT KELL HÍVNIA AZT A FÜGGVÉNYT, AMI AZ ÉRTÉKET KISZÁMOLJA!
        % Feltételezzük, hogy ez a függvény a 'calcHB' és az első outputja a keresett érték.
        HB_Ertek = NaN; % Alapértelmezett érték, ha a calcHB hívás hiányzik/hibás
        
        HB_Ertek = calcHB(SpO2, RespEvents, SleepStage, false); % true = legyen ábra

        % 5. LÉPÉS: Az eredmények eltárolása
        results{i, 1} = edfFajlNeve;
        results{i, 2} = HB_Ertek;
        
        fprintf('Feldolgozás sikeres. Eredmény: %.2f\n', HB_Ertek);
        
    catch ME
        % Hiba kezelése (ha egy fájl hibás, nem áll le a program, hanem folytatja)
        warning('Hiba történt a(z) %s fájl feldolgozása során: %s', edfFajlNeve, ME.message);
        results{i, 1} = edfFajlNeve;
        results{i, 2} = NaN; % Hibás fájl esetén "Not a Number" jelzés
    end
end

fprintf('\n\n=== Eredmények Összefoglalása ===\n');

% 6. LÉPÉS: Az eredmények táblázatban való megjelenítése
FinalTable = cell2table(results, 'VariableNames', {'FajlNeve', 'HB_Ertek'});

% Sortolás a HB érték szerint (opcionális)
FinalTable = sortrows(FinalTable, 'HB_Ertek', 'descend'); 

disp(FinalTable);

fprintf('\n=== Eredmények Excel exportálása ===\n');

% 1. LÉPÉS: Létrehozzuk a kiterjesztés nélküli fájlnevek oszlopát
% strrep: lecseréli a '.EDF' szöveget üres karakterláncra ('')
FajlNeveTisztitott = strrep(FinalTable.FajlNeve, '.EDF', '');

% 2. LÉPÉS: Létrehozzuk a végső táblázatot a kívánt oszloprenddel:
% 1. oszlop: Teljes Fájlnév
% 2. oszlop: Kiterjesztés Nélküli Fájlnév
% 3. oszlop: HB Érték
FinalTableExcel = table( ...
    FinalTable.FajlNeve, ...       % Teljes fájlnév
    FajlNeveTisztitott, ...        % Kiterjesztés nélküli fájlnév
    FinalTable.HB_Ertek, ...       % HB Érték
    'VariableNames', {'TeljesFajlNev', 'FajlNev', 'HB_Ertek'} ...
);

% 3. LÉPÉS: A táblázat kiírása Excel fájlba
excelFileName = 'HB_Eredmenyek_Osszefoglalo.xlsx';
writetable(FinalTableExcel, excelFileName);

fprintf('  Sikeres exportálás: %s\n', excelFileName);
fprintf('  A fájl az aktuális mappában található.\n');


%% A VÉGE
