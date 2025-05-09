ESX = nil

-- Fallback konfiguráció, ha a Config.lua nem töltődik be rendesen
if Config == nil then
    Config = {}
    -- NPC location coordinates
    Config.NPCCoords = vector4(-163.0158, -2129.9839, 16.7050, 211.1189)
    Config.KartSpawnCoords = vector4(-137.8276, -2147.6416, 16.7050, 286.0208)
    Config.ReturnCoords = vector4(-137.4859, -2152.0002, 16.7050, 100.1053)
    Config.InstructorSpawnCoords = vector4(-156.5069, -2154.5398, 16.7051, 40.3390)
    Config.LapCompletedNPCCoords = vector4(-159.5892, -2129.0410, 16.7050, 200.0222)
    Config.LapStartFinishCoords = vector4(-122.0248, -2121.6611, 16.7050, 290.8572)
    Config.ExtraKartBlipCoords = vector4(-153.1953, -2143.7898, 16.7050, 262.0619)

    -- Biztonsági beállítások
    Config.InteractionRadius = 10.0
    Config.ReturnRadius = 5.0
    Config.MaxDistanceFromTrack = 200.0
    Config.TrackCenter = vector3(-150.0, -2140.0, 16.7)
    Config.LapCheckpointRadius = 8.0
    
    -- Árak és időtartam
    Config.RentalPrice = 50
    Config.RentalDuration = 8
    Config.MonthlyPrice = 1200
    Config.BimonthlyPrice = 2000
    
    -- Modellek
    Config.NPCModel = "a_m_y_motox_01"
    Config.KartModel = "Shifter_kart"
    
    -- Játékélmény beállítások
    Config.SkipInstructorForExperienced = true -- Tapasztalt játékosoknak ne jelenjen meg az oktató
    
    print('[Karting] Config.lua nem található, fallback konfiguráció használata!')
end

local hasActiveSession = false
local sessionData = nil
local kartVehicle = nil
local instructorPed = nil
local kartingBlip = nil
local returnBlip = nil
local hasPurchasedMonthly = false
local monthlyExpiryDate = nil
local lapCompletedNPC = nil
local lapStartBlip = nil
local checkpointBlip = nil
local timeExpired = false
local hasSeenTutorial = false -- Új változó, amely jelzi, hogy látta-e már a játékos az oktatást

-- Session data for lap timing
local currentLap = 0
local lapStartTime = 0
local lapTimes = {}
local sessionStartTime = 0
local isRecordingLap = false

-- NPC location coordinates - áthelyezve a deklarációt az ESX inicializálás utánra
local npcCoords = nil
local kartSpawnCoords = nil
local returnCoords = nil
local instructorSpawnCoords = nil
local lapCompletedNPCCoords = nil
local lapStartFinishCoords = nil

-- The interaction radius - áthelyezve a deklarációt az ESX inicializálás utánra
local interactionRadius = nil
local returnRadius = nil
local maxDistanceFromTrack = nil
local trackCenter = nil

-- Lap checkpoints - áthelyezve a deklarációt az ESX inicializálás utánra
local lapStartFinish = nil
local lapCheckpointRadius = nil
local lapStarted = false
local passedCheckpoint = false

-- UI display state
local displayUI = false
local isResultsDisplayed = false
local menuInTransition = false -- Új állapotváltozó a menü átmenetekhez

-- Cache gyakran használt függvényeket
local GetEntityCoords = GetEntityCoords
local PlayerPedId = PlayerPedId
local GetGameTimer = GetGameTimer
local DrawMarker = DrawMarker
local Wait = Citizen.Wait
local DoesEntityExist = DoesEntityExist
local vector3 = vector3
local format = string.format
local floor = math.floor
local insert = table.insert

-- Initialize ESX
Citizen.CreateThread(function()
    while ESX == nil do
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        Wait(0)
    end
    
    -- Az ESX betöltése után inicializáljuk a koordinátákat a Config-ból
    npcCoords = Config.NPCCoords
    kartSpawnCoords = Config.KartSpawnCoords
    returnCoords = Config.ReturnCoords
    instructorSpawnCoords = Config.InstructorSpawnCoords
    lapCompletedNPCCoords = Config.LapCompletedNPCCoords
    lapStartFinishCoords = Config.LapStartFinishCoords

    -- Egyéb paraméterek inicializálása
    interactionRadius = Config.InteractionRadius
    returnRadius = Config.ReturnRadius
    maxDistanceFromTrack = Config.MaxDistanceFromTrack
    trackCenter = Config.TrackCenter
    lapStartFinish = vector3(Config.LapStartFinishCoords.x, Config.LapStartFinishCoords.y, Config.LapStartFinishCoords.z)
    lapCheckpointRadius = Config.LapCheckpointRadius
    
    print('[Karting] Változók sikeresen inicializálva a konfigurációból!')
    
    -- Check for subscription data
    TriggerServerEvent('karting:checkSubscription')
    
    -- Ellenőrizzük a tutorial állapotot
    ESX.TriggerServerCallback('karting:checkTutorialStatus', function(seen)
        hasSeenTutorial = seen
        print('[Karting] Tutorial status: ' .. (seen and 'Már látta' or 'Még nem látta'))
    end)
    
    -- Késleljük az NPC-k létrehozását, hogy a változók biztosan inicializálva legyenek
    Wait(1000)
    
    -- NPC-k és blipek létrehozása
    CreateNPCsAndBlips()
    
    -- Ellenőrizzük, hogy van-e aktív menet
    ESX.TriggerServerCallback('karting:checkActiveSession', function(active, data)
        if active then
            sessionData = data
            hasActiveSession = true
            
            -- Continue session if active
            TriggerEvent('karting:sessionStarted', data)
        end
    end)
end)

-- Függvény az NPC-k és blipek létrehozásához
function CreateNPCsAndBlips()
    -- Create the NPCs
    LoadModel(GetHashKey(Config.NPCModel))
    
    local npc = CreatePed(4, GetHashKey(Config.NPCModel), npcCoords.x, npcCoords.y, npcCoords.z - 1.0, npcCoords.w, false, true)
    FreezeEntityPosition(npc, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    
    -- Create lap completed NPC
    lapCompletedNPC = CreatePed(4, GetHashKey(Config.NPCModel), lapCompletedNPCCoords.x, lapCompletedNPCCoords.y, lapCompletedNPCCoords.z - 1.0, lapCompletedNPCCoords.w, false, true)
    FreezeEntityPosition(lapCompletedNPC, true)
    SetEntityInvincible(lapCompletedNPC, true)
    SetBlockingOfNonTemporaryEvents(lapCompletedNPC, true)
    
    -- Create the blip on the map
    kartingBlip = AddBlipForCoord(npcCoords.x, npcCoords.y, npcCoords.z)
    SetBlipSprite(kartingBlip, 315) -- Racing flag blip
    SetBlipDisplay(kartingBlip, 4)
    SetBlipScale(kartingBlip, 1.0) -- Nagyobb blip méret
    SetBlipColour(kartingBlip, 1) -- Red color
    SetBlipAsShortRange(kartingBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Gokart Pálya")
    EndTextCommandSetBlipName(kartingBlip)
    
    -- Create a circular area blip to show the track zone
    local trackBlip = AddBlipForRadius(trackCenter.x, trackCenter.y, trackCenter.z, 50.0) -- 50 méteres sugár
    SetBlipRotation(trackBlip, 0)
    SetBlipColour(trackBlip, 1) -- Piros
    SetBlipAlpha(trackBlip, 128) -- 50% átlátszóság
    
    -- Create the extra kart blip
    local extraKartBlip = AddBlipForCoord(Config.ExtraKartBlipCoords.x, Config.ExtraKartBlipCoords.y, Config.ExtraKartBlipCoords.z)
    SetBlipSprite(extraKartBlip, 348) -- Kart blip (348 = kis autó)
    SetBlipDisplay(extraKartBlip, 4)
    SetBlipScale(extraKartBlip, 0.7)
    SetBlipColour(extraKartBlip, 5) -- Sárga szín
    SetBlipAsShortRange(extraKartBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Gokart")
    EndTextCommandSetBlipName(extraKartBlip)
    
    -- Create the new karting blip at the specified coordinates
    local newKartingBlip = AddBlipForCoord(-162.7814, -2136.0759, 16.7050)
    SetBlipSprite(newKartingBlip, 348) -- Kart blip (348 = kis autó)
    SetBlipDisplay(newKartingBlip, 4)
    SetBlipScale(newKartingBlip, 0.7)
    SetBlipColour(newKartingBlip, 5) -- Sárga szín
    SetBlipAsShortRange(newKartingBlip, true)
    SetBlipRotation(newKartingBlip, math.floor(121.4545))
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Gokart")
    EndTextCommandSetBlipName(newKartingBlip)
    
    print('[Karting] NPC-k és blipek sikeresen létrehozva!')
end

-- Függvény a modellek betöltéséhez
local function LoadModel(model)
    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(1)
        end
    end
end

-- Main thread for NPC interaction and track functions
Citizen.CreateThread(function()
    -- Várunk amíg a változók inicializálódnak
    while npcCoords == nil do
        Wait(100)
    end
    
    -- Main loop for interaction - használjunk nagyobb várakozási időt, amikor nincs szükség gyakori frissítésre
    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local isNearMainNPC = false
        local isNearLapNPC = false
        local isNearReturnPoint = false
        local sleep = 1000 -- Alapértelmezett alvási idő, ha nincs semmi közel
        
        -- Távolságok számítása
        local distance = #(playerCoords - vector3(npcCoords.x, npcCoords.y, npcCoords.z))
        
        -- Ha közel van a fő NPC-hez
        if distance < interactionRadius then
            sleep = 0 -- Csökkent alvási idő, ha interakcióra van lehetőség
            isNearMainNPC = true
            
            if not hasActiveSession then
                -- Display interaction help text
                DrawMarker(1, npcCoords.x, npcCoords.y, npcCoords.z - 1.0, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 0.5, 255, 0, 0, 100, false, true, 2, false, nil, nil, false)
                
                if distance < 3.0 then
                    if hasPurchasedMonthly then
                        ESX.ShowHelpNotification("Nyomj ~INPUT_CONTEXT~ gombot a menühöz. Nyomj ~INPUT_DETONATE~ gombot az azonnali kartingozáshoz.")
                        
                        if IsControlJustReleased(0, 38) then -- E key
                            openKartingMenu()
                        elseif IsControlJustReleased(0, 47) then -- G key
                            startKartingSession("subscriber")
                        end
                    else
                        ESX.ShowHelpNotification("Nyomj ~INPUT_CONTEXT~ gombot a gokart bérléshez")
                        
                        if IsControlJustReleased(0, 38) then -- E key
                            openKartingMenu()
                        end
                    end
                end
            end
        end
        
        -- Csak akkor ellenőrizze a további interakciókat, ha aktív menet van
        if hasActiveSession then
            local lapNPCDistance = #(playerCoords - vector3(lapCompletedNPCCoords.x, lapCompletedNPCCoords.y, lapCompletedNPCCoords.z))
            local returnDistance = #(playerCoords - vector3(returnCoords.x, returnCoords.y, returnCoords.z))
            
            -- Ha közel van a lap completed NPC-hez
            if lapNPCDistance < 7.0 then
                sleep = 0
                isNearLapNPC = true
                
                DrawMarker(1, lapCompletedNPCCoords.x, lapCompletedNPCCoords.y, lapCompletedNPCCoords.z - 1.0, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 0.5, 255, 255, 0, 100, false, true, 2, false, nil, nil, false)
                
                if lapNPCDistance < 3.0 then
                    ESX.ShowHelpNotification("Nyomj ~INPUT_CONTEXT~ gombot az eredmények megtekintéséhez")
                    
                    if IsControlJustReleased(0, 38) then -- E key
                        if not isResultsDisplayed then
                            showLapResults()
                        end
                    end
                end
            end
            
            -- Ha közel van a visszaadási ponthoz
            if returnDistance < 7.0 then
                sleep = 0
                isNearReturnPoint = true
                
                DrawMarker(1, returnCoords.x, returnCoords.y, returnCoords.z - 1.0, 0, 0, 0, 0, 0, 0, 3.0, 3.0, 0.5, 255, 255, 0, 100, false, true, 2, false, nil, nil, false)
                
                if returnDistance < returnRadius then
                    ESX.ShowHelpNotification("Nyomj ~INPUT_CONTEXT~ gombot a gokart visszaadásához")
                    
                    if IsControlJustReleased(0, 38) then -- E key
                        endKartingSession()
                    end
                end
            end
            
            -- Távolság ellenőrzése és köridőmérés kezelése - minden keretben ellenőrizni kell
            sleep = 0
            
            -- Ha játékos túl messzire megy
            local distanceFromTrack = #(playerCoords - trackCenter)
            if distanceFromTrack > maxDistanceFromTrack and kartVehicle ~= nil then
                ESX.ShowNotification("Túl messzire távolodtál a gokart pályától!")
                DeleteVehicle(kartVehicle)
                kartVehicle = nil
                
                -- Teleport player back to the track
                SetEntityCoords(playerPed, returnCoords.x, returnCoords.y, returnCoords.z, true, false, false, false)
            end
            
            -- Köridőmérés kezelése
            local distanceToStartFinish = #(playerCoords - lapStartFinish)
            
            if distanceToStartFinish < lapCheckpointRadius then
                -- Ellenőrizzük a sebességet
                local playerVeh = GetVehiclePedIsIn(playerPed, false)
                local speed = 0
                
                if playerVeh ~= 0 then
                    speed = GetEntitySpeed(playerVeh) * 3.6 -- m/s -> km/h átváltás
                end
                
                if not lapStarted and not passedCheckpoint then
                    -- Start first lap
                    lapStarted = true
                    passedCheckpoint = true
                    lapStartTime = GetGameTimer()
                    if currentLap == 0 then
                        currentLap = 1
                        ESX.ShowNotification("1. kör kezdete!")
                    end
                    
                    -- Reset checkpoint after 8 seconds to prevent multiple triggers
                    Citizen.SetTimeout(8000, function()
                        passedCheckpoint = false
                    end)
                    
                elseif lapStarted and not passedCheckpoint then
                    -- Complete a lap
                    local lapTime = GetGameTimer() - lapStartTime
                    
                    -- Csak akkor fogadjuk el a kört, ha legalább 30 másodperc telt el a kezdés óta
                    -- A sebességet kijelezzük, de nem követeljük meg a minimum értéket
                    if lapTime > 30000 then
                        insert(lapTimes, lapTime)
                        
                        -- Record the lap time
                        TriggerServerEvent('karting:recordLapTime', lapTime)
                        
                        ESX.ShowNotification(currentLap .. ". kör: " .. formatTime(lapTime) .. " - " .. math.floor(speed) .. " km/h")
                        
                        -- Start a new lap
                        currentLap = currentLap + 1
                        lapStartTime = GetGameTimer()
                        passedCheckpoint = true
                        
                        -- Reset checkpoint after 8 seconds
                        Citizen.SetTimeout(8000, function()
                            passedCheckpoint = false
                        end)
                    else
                        -- Túl rövid a köridő - nem számoljuk
                        ESX.ShowNotification("~r~Érvénytelen köridő! Túl rövid a kör ideje.")
                        -- Továbbra is blokkoljuk a kört egy ideig
                        passedCheckpoint = true
                        Citizen.SetTimeout(5000, function()
                            passedCheckpoint = false
                        end)
                    end
                end
            end
            
            -- Lap start/finish marker rajzolása
            DrawMarker(4, lapStartFinish.x, lapStartFinish.y, lapStartFinish.z + 0.5, 0, 0, 0, 0, 0, lapStartFinishCoords.w, 3.0, 3.0, 1.5, 0, 255, 0, 100, false, true, 2, false, nil, nil, false)
        end
        
        Wait(sleep)
    end
end)

-- Függvény a HUD elemek megjelenítéséhez, hogy ne terheljük feleslegesen a rendszert
Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        
        if hasActiveSession then
            sleep = 0
            
            -- Idő kijelzése
            if sessionStartTime > 0 then
                local currentTime = GetGameTimer()
                local endTime = sessionStartTime + (Config.RentalDuration * 60 * 1000) -- Konfig értéket használjuk (perc -> millisec)
                
                if currentTime < endTime then
                    local remainingTime = floor((endTime - currentTime) / 1000)
                    local minutes = floor(remainingTime / 60)
                    local seconds = remainingTime % 60
                    
                    -- Display remaining time
                    local timeDisplay = format("Gokart bérlés: %02d:%02d", minutes, seconds)
                    DrawText2D(0.17, 0.94, timeDisplay, 0.4)
                    
                    -- Draw current lap and time
                    if lapStarted then
                        local currentLapTime = currentTime - lapStartTime
                        local lapTimeDisplay = "Kör " .. currentLap .. ": " .. formatTime(currentLapTime)
                        DrawText2D(0.17, 0.90, lapTimeDisplay, 0.4)
                    end
                else
                    -- Idő lejárt, de nem fejezzük be egyből a menetet, csak figyelmeztetjük a játékost
                    if not timeExpired then
                        timeExpired = true
                        ESX.ShowNotification("A gokart bérlésed ideje lejárt! Kérlek, hajtsd vissza a gokartot a visszaadási pontra!")
                        -- Piros színű figyelmeztetés megjelenítése
                        DrawText2D(0.17, 0.94, "IDŐ LEJÁRT! VIDD VISSZA A GOKARTOT!", 0.4)
                    else
                        -- Továbbra is jelenítjük meg a figyelmeztetést
                        DrawText2D(0.17, 0.94, "IDŐ LEJÁRT! VIDD VISSZA A GOKARTOT!", 0.4)
                    end
                    
                    -- Draw current lap and time even after time expired
                    if lapStarted then
                        local currentLapTime = currentTime - lapStartTime
                        local lapTimeDisplay = "Kör " .. currentLap .. ": " .. formatTime(currentLapTime)
                        DrawText2D(0.17, 0.90, lapTimeDisplay, 0.4)
                    end
                end
            end
        end
        
        Wait(sleep)
    end
end)

-- Function to format time in MM:SS.mmm format
function formatTime(ms)
    local totalSeconds = ms / 1000
    local minutes = floor(totalSeconds / 60)
    local seconds = floor(totalSeconds % 60)
    local milliseconds = floor((totalSeconds - floor(totalSeconds)) * 1000)
    
    return format("%02d:%02d.%03d", minutes, seconds, milliseconds)
end

-- Show lap results UI
function showLapResults()
    if #lapTimes == 0 then
        ESX.ShowNotification("Nincs még rögzített köridő. Fejezz be legalább egy kört!")
        return
    end
    
    -- Ha már megjelenítjük vagy átmenetben van, akkor nem nyitjuk meg újra
    if isResultsDisplayed or menuInTransition then
        return
    end
    
    menuInTransition = true
    isResultsDisplayed = true
    
    -- Find best lap
    local bestLap = lapTimes[1]
    for i = 2, #lapTimes do
        if lapTimes[i] < bestLap then
            bestLap = lapTimes[i]
        end
    end
    
    -- Calculate average lap time
    local totalTime = 0
    for _, time in ipairs(lapTimes) do
        totalTime = totalTime + time
    end
    local avgLap = totalTime / #lapTimes
    
    -- Get total session time
    local sessionTime = 0
    if sessionStartTime > 0 then
        sessionTime = GetGameTimer() - sessionStartTime
    end
    
    -- Create results object
    local results = {
        laps = #lapTimes,
        lapTimes = lapTimes,
        bestLap = bestLap,
        avgLap = avgLap,
        totalTime = sessionTime
    }
    
    -- Send results to UI
    SendNUIMessage({
        type = "sessionResults",
        results = results
    })
    
    -- Azonnal beállítjuk a fókuszt
    SetNuiFocus(true, true)
    
    -- Megjelenítünk egy üzenetet a játékosnak, hogy zárja be az eredményeket
    ESX.ShowNotification("Az eredmények megtekintése után kattints a 'Bezárás' gombra vagy nyomd meg az ESC billentyűt!")
    
    -- Átmeneti állapot feloldása
    Citizen.SetTimeout(500, function()
        menuInTransition = false
    end)
end

-- Function to open karting menu
function openKartingMenu()
    -- Ha már nyitva van vagy épp átmenetben van, ne csináljunk semmit
    if displayUI or menuInTransition then
        return
    end
    
    -- Beállítjuk, hogy átmenetben van a menü
    menuInTransition = true
    displayUI = true
    
    -- Fókusz beállítása
    SetNuiFocus(true, true)
    
    -- Get lap time data from server
    ESX.TriggerServerCallback('karting:getLapTimes', function(laptimeData)
        -- Csak akkor küldjük, ha még mindig nyitva kellene lennie
        if displayUI then
            SendNUIMessage({
                type = "open",
                title = "Gokart Pálya",
                price = Config.RentalPrice .. "$",
                duration = Config.RentalDuration .. " perc",
                isSubscriber = hasPurchasedMonthly,
                expiryDate = monthlyExpiryDate,
                laptimes = laptimeData or {} -- Biztosítjuk, hogy mindig van érték
            })
            
            -- Átmeneti állapot feloldása az üzenet elküldése után
            Citizen.SetTimeout(500, function()
                menuInTransition = false
            end)
        else
            -- Ha időközben be lett zárva, akkor biztosítsuk, hogy tényleg be van zárva
            SetNuiFocus(false, false)
            menuInTransition = false
        end
    end)
end

-- Function to close karting menu (including removing NUI focus)
function closeKartingMenu()
    -- Ha nincs nyitva vagy már átmenetben van, ne csináljunk semmit
    if not displayUI or menuInTransition then
        return
    end
    
    -- Beállítjuk, hogy átmenetben van
    menuInTransition = true
    displayUI = false
    
    -- Fókusz eltávolítása
    SetNuiFocus(false, false)
    
    -- Üzenet küldése a bezáráshoz
    SendNUIMessage({
        type = "close"
    })
    
    -- Kis késleltetéssel feloldjuk az átmeneti állapotot
    Citizen.SetTimeout(500, function()
        menuInTransition = false
        -- Még egyszer ellenőrizzük, hogy biztosan nincs fókusz
        if not displayUI then
            SetNuiFocus(false, false)
        end
    end)
end

-- Function to start karting session
function startKartingSession(sessionType, paymentMethod)
    TriggerServerEvent('karting:buySession', sessionType, paymentMethod)
end

-- Function to end karting session
function endKartingSession()
    if kartVehicle then
        DeleteVehicle(kartVehicle)
        kartVehicle = nil
    end
    
    if instructorPed then
        DeletePed(instructorPed)
        instructorPed = nil
    end
    
    if returnBlip then
        RemoveBlip(returnBlip)
        returnBlip = nil
    end
    
    if lapStartBlip then
        RemoveBlip(lapStartBlip)
        lapStartBlip = nil
    end
    
    if checkpointBlip then
        RemoveBlip(checkpointBlip)
        checkpointBlip = nil
    end
    
    -- Record session stats
    if #lapTimes > 0 then
        local bestLap = lapTimes[1]
        for i = 2, #lapTimes do
            if lapTimes[i] < bestLap then
                bestLap = lapTimes[i]
            end
        end
        
        TriggerServerEvent('karting:recordSession', {
            laps = #lapTimes,
            bestLap = bestLap
        })
        
        -- Show result UI one last time only if not already displayed
        if not isResultsDisplayed then
            showLapResults()
        end
    end
    
    -- Reset lap variables
    currentLap = 0
    lapStartTime = 0
    lapTimes = {}
    sessionStartTime = 0
    lapStarted = false
    passedCheckpoint = false
    timeExpired = false
    
    TriggerServerEvent('karting:endSession')
    hasActiveSession = false
    sessionData = nil
    
    ESX.ShowNotification("Gokart bérlésed véget ért. Köszönjük, hogy használtad szolgáltatásunkat!")
end

-- NUI Callbacks
RegisterNUICallback('closeMenu', function(data, cb)
    closeKartingMenu()
    cb('ok')
end)

RegisterNUICallback('purchaseSession', function(data, cb)
    -- Ha átmenetben van, nem engedjük
    if menuInTransition then
        cb('ok')
        return
    end
    
    menuInTransition = true
    
    -- Bezárjuk a menüt
    displayUI = false
    SendNUIMessage({
        type = "close"
    })
    SetNuiFocus(false, false)
    
    -- Session indítása a fizetési móddal
    startKartingSession(data.type, data.paymentMethod)
    
    -- Késleltetve oldjuk fel az átmeneti állapotot
    Citizen.SetTimeout(500, function()
        menuInTransition = false
    end)
    
    cb('ok')
end)

RegisterNUICallback('closeResults', function(data, cb)
    -- Ha átmenetben van, nem engedjük
    if menuInTransition then
        cb('ok')
        return
    end
    
    menuInTransition = true
    isResultsDisplayed = false
    
    SetNuiFocus(false, false)
    
    ESX.ShowNotification("Eredmények bezárva. Köszönjük, hogy használtad a gokart pályát!")
    
    -- Késleltetve oldjuk fel az átmeneti állapotot
    Citizen.SetTimeout(500, function()
        menuInTransition = false
    end)
    
    cb('ok')
end)

-- Event handler for session started
RegisterNetEvent('karting:sessionStarted')
AddEventHandler('karting:sessionStarted', function(data)
    hasActiveSession = true
    sessionData = data
    
    -- Előző bérlésről információ megjelenítése
    if hasSeenTutorial then
        ESX.ShowHelpNotification("~g~Tapasztalt versenyző vagy. Jó szórakozást!")
    else
        ESX.ShowHelpNotification("~y~Első alkalommal kartingozol. Figyelj az oktató utasításaira!")
    end
    
    -- Reset lap data
    currentLap = 0
    lapStartTime = 0
    lapTimes = {}
    sessionStartTime = GetGameTimer()
    lapStarted = false
    
    -- Spawn the kart
    LoadModel(GetHashKey(Config.KartModel))
    
    kartVehicle = CreateVehicle(GetHashKey(Config.KartModel), kartSpawnCoords.x, kartSpawnCoords.y, kartSpawnCoords.z, kartSpawnCoords.w, true, false)
    SetVehicleOnGroundProperly(kartVehicle)
    
    -- Create instructor ped
    LoadModel(GetHashKey(Config.NPCModel))
    
    local playerPed = PlayerPedId()
    
    -- Teleport player to the kart
    TaskWarpPedIntoVehicle(playerPed, kartVehicle, -1) -- -1 is the driver seat
    
    -- Ha már látta a szabályokat, akkor nem kell az oktató
    if hasSeenTutorial and Config.SkipInstructorForExperienced then
        -- Tapasztalt játékosoknak nincs oktató, egyből kezdhetik
        ESX.ShowNotification("~g~Egyből kezdhetsz versenyezni, mivel már ismered a szabályokat!")
    else
        -- Create the instructor at the spawn point and make him walk towards player
        instructorPed = CreatePed(4, GetHashKey(Config.NPCModel), instructorSpawnCoords.x, instructorSpawnCoords.y, instructorSpawnCoords.z, instructorSpawnCoords.w, true, false)
        SetEntityInvincible(instructorPed, true)
        SetBlockingOfNonTemporaryEvents(instructorPed, true)
        
        -- Make the instructor walk to the player
        local playerPosition = GetEntityCoords(playerPed)
        TaskGoToEntity(instructorPed, playerPed, -1, 2.0, 1.5, 0, 0)
        
        -- Wait until instructor arrives near player
        Citizen.CreateThread(function()
            local arrived = false
            
            while not arrived and DoesEntityExist(instructorPed) and hasActiveSession do
                Wait(500)
                
                local instructorCoords = GetEntityCoords(instructorPed)
                local playerCoords = GetEntityCoords(playerPed)
                local distance = #(instructorCoords - playerCoords)
                
                if distance < 3.0 then
                    arrived = true
                    ClearPedTasks(instructorPed)
                    
                    -- Make instructor face the player
                    TaskTurnPedToFaceEntity(instructorPed, playerPed, -1)
                    
                    -- Display instructor speech
                    displayInstructorSpeech()
                end
            end
        end)
    end
    
    -- Set a blip for the return point
    returnBlip = AddBlipForCoord(returnCoords.x, returnCoords.y, returnCoords.z)
    SetBlipSprite(returnBlip, 358) -- Garage blip
    SetBlipDisplay(returnBlip, 4)
    SetBlipScale(returnBlip, 0.8)
    SetBlipColour(returnBlip, 5) -- Yellow color
    SetBlipAsShortRange(returnBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Gokart Visszaadás")
    EndTextCommandSetBlipName(returnBlip)
    
    -- Set a blip for the lap start/finish line
    lapStartBlip = AddBlipForCoord(lapStartFinish.x, lapStartFinish.y, lapStartFinish.z)
    SetBlipSprite(lapStartBlip, 38) -- Checkered flag blip
    SetBlipDisplay(lapStartBlip, 4)
    SetBlipScale(lapStartBlip, 0.8)
    SetBlipColour(lapStartBlip, 2) -- Green color
    SetBlipAsShortRange(lapStartBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Kezdő/Célvonal")
    EndTextCommandSetBlipName(lapStartBlip)
    
    -- Add checkpoint blip
    checkpointBlip = AddBlipForCoord(lapStartFinish.x, lapStartFinish.y, lapStartFinish.z)
    SetBlipSprite(checkpointBlip, 315) -- Checkpoint blip
    SetBlipDisplay(checkpointBlip, 4)
    SetBlipScale(checkpointBlip, 1.0)
    SetBlipColour(checkpointBlip, 2) -- Green color
    SetBlipAsShortRange(checkpointBlip, true)
    SetBlipRotation(checkpointBlip, math.floor(lapStartFinishCoords.w))
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Checkpoint")
    EndTextCommandSetBlipName(checkpointBlip)
end)

-- Function to display the instructor's speech
function displayInstructorSpeech()
    -- Ha a játékos már látta az oktatást, akkor nem mutatjuk újra
    if hasSeenTutorial then
        if DoesEntityExist(instructorPed) then
            DeletePed(instructorPed)
            instructorPed = nil
        end
        
        -- Értesítés a játékosnak, hogy már ismeri a szabályokat
        ESX.ShowNotification("~g~Üdvözlünk újra a gokart pályán! Mivel már ismered a szabályokat, most már egyből kezdhetsz.")
        
        return
    end
    
    -- Első oktató után beállítjuk, hogy már látta
    hasSeenTutorial = true
    TriggerServerEvent('karting:saveTutorialStatus', true)
    
    ESX.ShowNotification("~y~Első alkalommal kartingozol. Figyelj az oktató szabálymagyarázatára!")

    Citizen.CreateThread(function()
        local rules = {
            "Üdvözöllek a gokart pályán!",
            "Szabályok:",
            "1. Vezess óvatosan, ne okozz balesetet!",
            "2. Kövesd a pálya vonalát!",
            "3. " .. Config.RentalDuration .. " perced van a gokartozásra.",
            "4. Időben hozd vissza a gokartot!",
            "5. Az időméréshez a kezdő/célvonalnál kell áthaladni!",
            "6. Jó szórakozást!"
        }
        
        for i = 1, #rules do
            local rule = rules[i]
            
            -- Display the rule as a thought bubble above instructor's head
            Citizen.CreateThread(function()
                local startTime = GetGameTimer()
                local endTime = startTime + 2500 -- 2.5 másodperc minden szabályra (felgyorsítva)
                
                while GetGameTimer() < endTime and hasActiveSession and DoesEntityExist(instructorPed) do
                    local instructorCoords = GetEntityCoords(instructorPed)
                    DrawText3D(instructorCoords.x, instructorCoords.y, instructorCoords.z + 1.0, rule)
                    Wait(0)
                end
            end)
            
            Wait(2500) -- 2.5 másodperc várakozás a következő szabály előtt
        end
        
        -- After finishing rules, make the instructor walk back
        Wait(1000) -- Csökkentett várakozás
        
        if DoesEntityExist(instructorPed) and hasActiveSession then
            TaskGoToCoordAnyMeans(instructorPed, instructorSpawnCoords.x, instructorSpawnCoords.y, instructorSpawnCoords.z, 1.5, 0, 0, 786603, 0)
            
            -- Wait until instructor gets back to original position
            Citizen.CreateThread(function()
                local returnedToSpawn = false
                
                while not returnedToSpawn and DoesEntityExist(instructorPed) and hasActiveSession do
                    Wait(500)
                    
                    local instructorCoords = GetEntityCoords(instructorPed)
                    local spawnDistance = #(instructorCoords - vector3(instructorSpawnCoords.x, instructorSpawnCoords.y, instructorSpawnCoords.z))
                    
                    if spawnDistance < 2.0 then
                        returnedToSpawn = true
                        ClearPedTasks(instructorPed)
                        SetEntityHeading(instructorPed, instructorSpawnCoords.w)
                        DeletePed(instructorPed)
                        instructorPed = nil
                    end
                end
            end)
        end
    end)
end

-- Function to disable player from starting the kart until speech is completed
Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        
        if hasActiveSession and instructorPed then
            sleep = 0
            DisableControlAction(0, 71, true) -- Disable accelerate
            DisableControlAction(0, 72, true) -- Disable reverse
            DisableControlAction(0, 76, true) -- Disable handbrake
            
            -- Check if the instructor is gone (speech finished)
            if not DoesEntityExist(instructorPed) then
                -- Re-enable controls
                EnableControlAction(0, 71, true)
                EnableControlAction(0, 72, true)
                EnableControlAction(0, 76, true)
            end
        end
        
        Wait(sleep)
    end
end)

-- Helper function to draw 3D text in the world (thought bubble style)
function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    local px, py, pz = table.unpack(GetGameplayCamCoords())
    
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
        
        local factor = (string.len(text)) / 370
        DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 41, 41, 41, 120)
    end
end

-- Helper function to draw 2D text on the screen
function DrawText2D(x, y, text, scale)
    SetTextFont(4)
    SetTextProportional(7)
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 255)
    SetTextDropShadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

-- Register subscription events
RegisterNetEvent('karting:subscriptionData')
AddEventHandler('karting:subscriptionData', function(hasSubscription, expiryTimestamp)
    hasPurchasedMonthly = hasSubscription
    
    if expiryTimestamp then
        local expiryDate = os.date("%Y. %m. %d. %H:%M", expiryTimestamp)
        monthlyExpiryDate = expiryDate
    else
        monthlyExpiryDate = nil
    end
end)

-- Register tutorial status update event
RegisterNetEvent('karting:tutorialStatus')
AddEventHandler('karting:tutorialStatus', function(seen)
    hasSeenTutorial = seen
    print('[Karting] Tutorial status frissítve: ' .. (seen and 'Már látta' or 'Még nem látta'))
end)