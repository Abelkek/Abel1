ESX = nil

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

-- Fallback konfiguráció, ha a Config.lua nem töltődik be rendesen
if Config == nil then
    Config = {}
    -- Árak és időtartam
    Config.RentalPrice = 50
    Config.RentalDuration = 8
    Config.MonthlyPrice = 1200
    Config.BimonthlyPrice = 2000
    
    print('[Karting] Config.lua nem található a szerveren, fallback konfiguráció használata!')
end

-- Renters data storage
local renters = {}
local subscribers = {}
local tutorialSeen = {}

-- Játékos csatlakozásakor ellenőrizzük az előfizetését
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local identifier = xPlayer.identifier
    -- Ellenőrizzük az előfizetést
    MySQL.Async.fetchAll('SELECT * FROM karting_subscriptions WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(results)
        if results and #results > 0 then
            local subscription = results[1]
            
            if os.time() < subscription.expiry_date then
                -- Valid subscription
                subscribers[identifier] = {
                    expiryDate = subscription.expiry_date,
                    type = subscription.subscription_type
                }
                TriggerClientEvent('karting:subscriptionData', playerId, true, subscription.expiry_date)
                TriggerClientEvent('esx:showNotification', playerId, 'Aktív gokart előfizetésed van! Lejárat: ' .. os.date("%Y. %m. %d. %H:%M", subscription.expiry_date))
            else
                -- Expired subscription, remove from database
                MySQL.Async.execute('DELETE FROM karting_subscriptions WHERE identifier = @identifier', {
                    ['@identifier'] = identifier
                })
                TriggerClientEvent('karting:subscriptionData', playerId, false, nil)
            end
        end
    end)
    
    -- Ellenőrizzük a tutorial állapotot is
    MySQL.Async.fetchScalar('SELECT seen_tutorial FROM karting_tutorial WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(result)
        if result ~= nil then
            tutorialSeen[identifier] = (result == 1)
            -- Tutorial állapot küldése a kliensnek
            TriggerClientEvent('karting:tutorialStatus', playerId, tutorialSeen[identifier])
        end
    end)
end)

-- Register server event for purchasing karting session
RegisterServerEvent('karting:buySession')
AddEventHandler('karting:buySession', function(sessionType, paymentMethod)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    
    local cost = Config.RentalPrice -- A konfigurációból vesszük az értéket
    
    if sessionType == "monthly" then
        cost = Config.MonthlyPrice -- A konfigurációból vesszük az értéket
    elseif sessionType == "bimonthly" then
        cost = Config.BimonthlyPrice -- A konfigurációból vesszük az értéket
    elseif sessionType == "subscriber" then
        -- Check if player is a subscriber
        local identifier = xPlayer.identifier
        
        if subscribers[identifier] then
            if os.time() < subscribers[identifier].expiryDate then
                -- Free session for subscriber
                cost = 0
            else
                -- Subscription expired
                subscribers[identifier] = nil
                TriggerClientEvent('esx:showNotification', _source, 'Előfizetésed lejárt! Kérlek vásárolj újat!')
                TriggerClientEvent('karting:subscriptionData', _source, false, nil)
                return
            end
        else
            TriggerClientEvent('esx:showNotification', _source, 'Nincs aktív előfizetésed!')
            return
        end
    end
    
    -- Fizetési mód ellenőrzése (készpénz vagy bankkártya)
    local canPay = false
    
    if paymentMethod == "bank" then
        -- Bankkártyás fizetés
        if xPlayer.getAccount('bank').money >= cost then
            canPay = true
            if cost > 0 then
                xPlayer.removeAccountMoney('bank', cost)
                TriggerClientEvent('esx:showNotification', _source, 'A bankszámládról levonásra került: ~r~' .. cost .. '$')
            end
        end
    else
        -- Készpénzes fizetés (alapértelmezett)
        if xPlayer.getMoney() >= cost then
            canPay = true
            if cost > 0 then
                xPlayer.removeMoney(cost)
            end
        end
    end
    
    if canPay then
        -- Handle subscription purchases
        if sessionType == "monthly" or sessionType == "bimonthly" then
            local identifier = xPlayer.identifier
            local duration = 30 -- 30 days for monthly
            
            if sessionType == "bimonthly" then
                duration = 60 -- 60 days for bimonthly
            end
            
            local expiryDate = os.time() + (duration * 24 * 60 * 60) -- Convert days to seconds
            
            subscribers[identifier] = {
                expiryDate = expiryDate,
                type = sessionType
            }
            
            -- Save data to database for persistence
            MySQL.Async.execute('DELETE FROM karting_subscriptions WHERE identifier = @identifier', {
                ['@identifier'] = identifier
            }, function()
                MySQL.Async.execute('INSERT INTO karting_subscriptions (identifier, expiry_date, subscription_type) VALUES (@identifier, @expiry_date, @subscription_type)', {
                    ['@identifier'] = identifier,
                    ['@expiry_date'] = expiryDate,
                    ['@subscription_type'] = sessionType
                })
                
                -- Log purchase in separate table for record keeping
                MySQL.Async.execute('INSERT INTO karting_purchases (identifier, purchase_type, price, expiry_date, purchase_date, payment_method) VALUES (@identifier, @purchase_type, @price, @expiry_date, @purchase_date, @payment_method)', {
                    ['@identifier'] = identifier,
                    ['@purchase_type'] = sessionType,
                    ['@price'] = cost,
                    ['@expiry_date'] = expiryDate,
                    ['@purchase_date'] = os.time(),
                    ['@payment_method'] = paymentMethod or "cash"
                })
            end)
            
            -- Send subscription data to client
            TriggerClientEvent('karting:subscriptionData', _source, true, expiryDate)
            
            if sessionType == "monthly" then
                TriggerClientEvent('esx:showNotification', _source, 'Sikeres vásárlás: Havi gokart bérlet - ' .. Config.MonthlyPrice .. '$')
            else
                TriggerClientEvent('esx:showNotification', _source, 'Sikeres vásárlás: Kéthavi gokart bérlet - ' .. Config.BimonthlyPrice .. '$')
            end
        end
        
        -- Always create a rental session
        renters[_source] = {
            identifier = xPlayer.identifier,
            startTime = os.time(),
            endTime = os.time() + (Config.RentalDuration * 60), -- 8 minutes in seconds, konfigból vesszük
            sessionType = sessionType
        }
        
        TriggerClientEvent('karting:sessionStarted', _source, renters[_source])
        
        if sessionType == "single" then
            TriggerClientEvent('esx:showNotification', _source, 'Sikeres vásárlás: Gokart bérlés - ' .. Config.RentalDuration .. ' perc / ' .. Config.RentalPrice .. '$')
        elseif sessionType == "subscriber" then
            TriggerClientEvent('esx:showNotification', _source, 'Gokart bérlés előfizetői kör. Jó szórakozást!')
        end
    else
        local priceTable = {
            single = Config.RentalPrice .. '$',
            monthly = Config.MonthlyPrice .. '$',
            bimonthly = Config.BimonthlyPrice .. '$'
        }
        
        local paymentText = paymentMethod == "bank" and "a bankszámládról" or "készpénzben"
        TriggerClientEvent('esx:showNotification', _source, 'Nincs elég pénzed ' .. paymentText .. '! Szükséges: ' .. (priceTable[sessionType] or Config.RentalPrice .. '$'))
    end
end)

-- Event when a player leaves
AddEventHandler('playerDropped', function()
    local _source = source
    if renters[_source] then
        renters[_source] = nil
    end
end)

-- Register server event for ending karting session
RegisterServerEvent('karting:endSession')
AddEventHandler('karting:endSession', function()
    local _source = source
    if renters[_source] then
        renters[_source] = nil
        TriggerClientEvent('esx:showNotification', _source, 'Gokart bérlés befejeződött.')
    end
end)

-- Check if player has an active session
ESX.RegisterServerCallback('karting:checkActiveSession', function(source, cb)
    local _source = source
    if renters[_source] then
        if os.time() > renters[_source].endTime then
            renters[_source] = nil
            cb(false)
        else
            cb(true, renters[_source])
        end
    else
        cb(false)
    end
end)

-- Register server event for checking subscription
RegisterServerEvent('karting:checkSubscription')
AddEventHandler('karting:checkSubscription', function()
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    
    if not xPlayer then
        return
    end
    
    local identifier = xPlayer.identifier
    
    -- Check if player is already in memory
    if subscribers[identifier] then
        if os.time() < subscribers[identifier].expiryDate then
            TriggerClientEvent('karting:subscriptionData', _source, true, subscribers[identifier].expiryDate)
        else
            -- Subscription expired, remove it
            subscribers[identifier] = nil
            MySQL.Async.execute('DELETE FROM karting_subscriptions WHERE identifier = @identifier', {
                ['@identifier'] = identifier
            })
            TriggerClientEvent('karting:subscriptionData', _source, false, nil)
        end
    else
        -- Check from database
        MySQL.Async.fetchAll('SELECT * FROM karting_subscriptions WHERE identifier = @identifier', {
            ['@identifier'] = identifier
        }, function(results)
            if results and #results > 0 then
                local subscription = results[1]
                
                if os.time() < subscription.expiry_date then
                    -- Valid subscription
                    subscribers[identifier] = {
                        expiryDate = subscription.expiry_date,
                        type = subscription.subscription_type
                    }
                    TriggerClientEvent('karting:subscriptionData', _source, true, subscription.expiry_date)
                else
                    -- Expired subscription, remove from database
                    MySQL.Async.execute('DELETE FROM karting_subscriptions WHERE identifier = @identifier', {
                        ['@identifier'] = identifier
                    })
                    TriggerClientEvent('karting:subscriptionData', _source, false, nil)
                end
            else
                TriggerClientEvent('karting:subscriptionData', _source, false, nil)
            end
        end)
    end
end)

-- Register server event for recording lap time
RegisterServerEvent('karting:recordLapTime')
AddEventHandler('karting:recordLapTime', function(lapTime)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    
    if not xPlayer then
        return
    end
    
    local identifier = xPlayer.identifier
    local playerName = GetPlayerName(_source)
    local currentDate = os.date("*t")
    local currentDay = currentDate.day
    local currentMonth = currentDate.month
    local currentYear = currentDate.year
    
    -- Get player's name from ESX
    MySQL.Async.fetchScalar('SELECT firstname || " " || lastname FROM users WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(fullName)
        local name = fullName or playerName or "Unknown Player"
        
        -- Save the laptime to the database
        MySQL.Async.execute('INSERT INTO karting_laptimes (identifier, name, lap_time, date) VALUES (@identifier, @name, @lap_time, @date)', {
            ['@identifier'] = identifier,
            ['@name'] = name,
            ['@lap_time'] = lapTime,
            ['@date'] = os.time()
        })
    end)
end)

-- Register server event for recording a complete session
RegisterServerEvent('karting:recordSession')
AddEventHandler('karting:recordSession', function(sessionData)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    
    if not xPlayer then
        return
    end
    
    local identifier = xPlayer.identifier
    
    -- Record the session data in database
    MySQL.Async.execute('INSERT INTO karting_sessions (identifier, laps, best_lap, date) VALUES (@identifier, @laps, @best_lap, @date)', {
        ['@identifier'] = identifier,
        ['@laps'] = sessionData.laps,
        ['@best_lap'] = sessionData.bestLap,
        ['@date'] = os.time()
    })
end)

-- Get lap times
ESX.RegisterServerCallback('karting:getLapTimes', function(source, cb)
    local currentTime = os.time()
    local today = os.date("*t", currentTime)
    local startOfDay = os.time({year = today.year, month = today.month, day = today.day, hour = 0, min = 0, sec = 0})
    local startOfMonth = os.time({year = today.year, month = today.month, day = 1, hour = 0, min = 0, sec = 0})
    local startOfYear = os.time({year = today.year, month = 1, day = 1, hour = 0, min = 0, sec = 0})
    
    -- Kezdetben üres tömböket adunk vissza
    local laptimes = {
        daily = {},
        monthly = {},
        yearly = {}
    }
    
    -- Ellenőrizzük, hogy létezik-e az adatbázis és a táblák
    MySQL.Async.fetchScalar("SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'karting_laptimes'", {}, function(tableExists)
        if tableExists and tonumber(tableExists) > 0 then
            -- Adatbázis létezik, lekérdezzük az adatokat
            
            -- Get daily best laptimes
            MySQL.Async.fetchAll('SELECT name, MIN(lap_time) as time FROM karting_laptimes WHERE date >= @startOfDay GROUP BY identifier ORDER BY time ASC LIMIT 10', {
                ['@startOfDay'] = startOfDay
            }, function(dailyResults)
                if dailyResults then
                    laptimes.daily = formatLaptimes(dailyResults)
                end
                
                -- Get monthly best laptimes
                MySQL.Async.fetchAll('SELECT name, MIN(lap_time) as time FROM karting_laptimes WHERE date >= @startOfMonth GROUP BY identifier ORDER BY time ASC LIMIT 10', {
                    ['@startOfMonth'] = startOfMonth
                }, function(monthlyResults)
                    if monthlyResults then
                        laptimes.monthly = formatLaptimes(monthlyResults)
                    end
                    
                    -- Get yearly best laptimes
                    MySQL.Async.fetchAll('SELECT name, MIN(lap_time) as time FROM karting_laptimes WHERE date >= @startOfYear GROUP BY identifier ORDER BY time ASC LIMIT 10', {
                        ['@startOfYear'] = startOfYear
                    }, function(yearlyResults)
                        if yearlyResults then
                            laptimes.yearly = formatLaptimes(yearlyResults)
                        end
                        
                        cb(laptimes)
                    end)
                end)
            end)
        else
            -- Adatbázis nem létezik, üres eredményt adunk vissza
            cb(laptimes)
        end
    end)
end)

-- Helper function to format lap times
function formatLaptimes(results)
    local formatted = {}
    
    for i, result in ipairs(results) do
        table.insert(formatted, {
            name = result.name,
            time = result.time
        })
    end
    
    return formatted
end

-- Register server event for saving tutorial status
RegisterServerEvent('karting:saveTutorialStatus')
AddEventHandler('karting:saveTutorialStatus', function(status)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    
    if not xPlayer then
        return
    end
    
    local identifier = xPlayer.identifier
    tutorialSeen[identifier] = status
    
    -- Mentés az adatbázisba
    MySQL.Async.execute('DELETE FROM karting_tutorial WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function()
        MySQL.Async.execute('INSERT INTO karting_tutorial (identifier, seen_tutorial) VALUES (@identifier, @seen_tutorial)', {
            ['@identifier'] = identifier,
            ['@seen_tutorial'] = status and 1 or 0
        })
    end)
end)

-- Register server callback for checking tutorial status
ESX.RegisterServerCallback('karting:checkTutorialStatus', function(source, cb)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    
    if not xPlayer then
        cb(false)
        return
    end
    
    local identifier = xPlayer.identifier
    
    -- Ha már a memóriában van
    if tutorialSeen[identifier] ~= nil then
        cb(tutorialSeen[identifier])
        return
    end
    
    -- Ellenőrizzük az adatbázisban
    MySQL.Async.fetchScalar('SELECT seen_tutorial FROM karting_tutorial WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(result)
        if result ~= nil then
            tutorialSeen[identifier] = (result == 1)
            cb(tutorialSeen[identifier])
        else
            tutorialSeen[identifier] = false
            cb(false)
        end
    end)
end)

-- Create database tables if they don't exist
MySQL.ready(function()
    print('[Karting] MySQL kapcsolat létrejött, adatbázis táblák ellenőrzése...')
    
    -- Create subscription table
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `karting_subscriptions` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `expiry_date` int(11) NOT NULL,
            `subscription_type` varchar(20) NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `identifier` (`identifier`)
        );
    ]], {}, function(rowsChanged)
        print('[Karting] karting_subscriptions tábla ellenőrizve.')
    end)
    
    -- Create purchases table to record all subscription purchases
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `karting_purchases` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `purchase_type` varchar(20) NOT NULL,
            `price` int(11) NOT NULL,
            `expiry_date` int(11) NOT NULL,
            `purchase_date` int(11) NOT NULL,
            `payment_method` varchar(10) NOT NULL DEFAULT 'cash',
            PRIMARY KEY (`id`),
            KEY `identifier` (`identifier`),
            KEY `purchase_date` (`purchase_date`)
        );
    ]], {}, function(rowsChanged)
        print('[Karting] karting_purchases tábla ellenőrizve.')
    end)
    
    -- Create laptimes table
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `karting_laptimes` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `name` varchar(50) NOT NULL,
            `lap_time` int(11) NOT NULL,
            `date` int(11) NOT NULL,
            PRIMARY KEY (`id`),
            KEY `identifier` (`identifier`),
            KEY `date` (`date`)
        );
    ]], {}, function(rowsChanged)
        print('[Karting] karting_laptimes tábla ellenőrizve.')
    end)
    
    -- Create sessions table
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `karting_sessions` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `laps` int(5) NOT NULL,
            `best_lap` int(11) NOT NULL,
            `date` int(11) NOT NULL,
            PRIMARY KEY (`id`),
            KEY `identifier` (`identifier`),
            KEY `date` (`date`)
        );
    ]], {}, function(rowsChanged)
        print('[Karting] karting_sessions tábla ellenőrizve.')
    end)
    
    -- Create tutorial table
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `karting_tutorial` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `seen_tutorial` tinyint(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            UNIQUE KEY `identifier` (`identifier`)
        );
    ]], {}, function(rowsChanged)
        print('[Karting] karting_tutorial tábla ellenőrizve.')
    end)
end) 