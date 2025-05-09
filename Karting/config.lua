Config = {}

-- Alapértelmezett nyelv
Config.Locale = 'en'

-- Árak és időtartam
Config.RentalPrice = 50               -- Gokart bérlés ára (dollár)
Config.RentalDuration = 8             -- Gokart bérlés időtartama (perc)
Config.MonthlyPrice = 1200            -- Havi bérlet ára
Config.BimonthlyPrice = 2000          -- Kéthavi bérlet ára

-- Koordináták
Config.NPCCoords = vector4(-163.0158, -2129.9839, 16.7050, 211.1189)                -- NPC helyzetkoordinátái
Config.KartSpawnCoords = vector4(-137.8276, -2147.6416, 16.7050, 286.0208)         -- Gokart megjelenés koordinátái
Config.ReturnCoords = vector4(-137.4859, -2152.0002, 16.7050, 100.1053)            -- Visszaadási pont koordinátái
Config.InstructorSpawnCoords = vector4(-156.5069, -2154.5398, 16.7051, 40.3390)    -- Oktató megjelenése
Config.LapCompletedNPCCoords = vector4(-158.3965, -2128.1174, 16.7050, 219.5378) 
Config.LapStartFinishCoords = vector4(-122.0248, -2121.6611, 16.7050, 290.8572)    -- Köridő kezdő/célvonal - 4 méterrel hátrébb húzva
Config.ExtraKartBlipCoords = vector4(-153.1953, -2143.7898, 16.7050, 262.0619)     -- Extra gokart blip koordináta

-- Biztonsági beállítások
Config.MaxDistanceFromTrack = 200.0   -- Max távolság a pályától (méter)
Config.TrackCenter = vector3(-150.0, -2140.0, 16.7)   -- Pálya közepének koordinátái

-- Sugarak és távolságok
Config.InteractionRadius = 10.0       -- NPC interakciós sugara (méter)
Config.ReturnRadius = 5.0             -- Visszaadási pont sugara (méter)
Config.LapCheckpointRadius = 8.0      -- Köridő ellenőrzőpont sugara (méter)

-- Modellek
Config.NPCModel = "a_m_y_motox_01"    -- NPC modell
Config.KartModel = "Shifter_kart"     -- Gokart modell 

-- Játékélmény beállítások
Config.SkipInstructorForExperienced = true -- Tapasztalt játékosoknak ne jelenjen meg az oktató NPC 