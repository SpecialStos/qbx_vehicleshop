local config = require 'config.client'
local sharedConfig = require 'config.shared'
local VEHICLES = exports.qbx_core:GetVehiclesByName()
local VEHICLES_HASH = exports.qbx_core:GetVehiclesByHash()
local testDriveVeh = 0
local inTestDrive = false
local insideShop = nil

---@class VehicleFinanceClient
---@field vehiclePlate string
---@field balance number
---@field paymentsLeft integer
---@field paymentAmount number

---@param data VehicleFinanceClient
local function financePayment(data)
    local dialog = lib.inputDialog(Lang:t('menus.veh_finance'), {
        {
            type = 'number',
            label = Lang:t('menus.veh_finance_payment'),
        }
    })

    if not dialog then return end

    local paymentAmount = tonumber(dialog[1])
    TriggerServerEvent('qbx_vehicleshop:server:financePayment', paymentAmount, data)
end

local function confirmationCheck()
    local alert = lib.alertDialog({
        header = 'Wait a minute!',
        content = 'Are you sure you wish to proceed?',
        centered = true,
        cancel = true,
        labels = {
            cancel = 'No',
            confirm = 'Yes',
        }
    })
    return alert
end

---@param data VehicleFinanceClient
local function showVehicleFinanceMenu(data)
    local vehLabel = VEHICLES[data.vehicle].brand..' '..VEHICLES[data.vehicle].name
    local vehFinance = {
        {
            title = 'Finance Information',
            icon = 'circle-info',
            description = string.format('Name: %s\nPlate: %s\nRemaining Balance: $%s\nRecurring Payment Amount: $%s\nPayments Left: %s', vehLabel, data.vehiclePlate, CommaValue(data.balance), CommaValue(data.paymentAmount), data.paymentsLeft),
            readOnly = true,
        },
        {
            title = Lang:t('menus.veh_finance_pay'),
            onSelect = function()
                financePayment(data)
            end,
        },
        {
            title = Lang:t('menus.veh_finance_payoff'),
            onSelect = function()
                local check = confirmationCheck()
                if check == 'confirm' then
                    TriggerServerEvent('qbx_vehicleshop:server:financePaymentFull', {vehBalance = data.balance, vehPlate = data.vehiclePlate})
                else
                    lib.showContext('vehicleFinance')
                end
            end,
        },
    }

    lib.registerContext({
        id = 'vehicleFinance',
        title = Lang:t('menus.financed_header'),
        menu = 'ownedVehicles',
        options = vehFinance
    })

    lib.showContext('vehicleFinance')
end

--- Gets the owned vehicles based on financing then opens a menu
local function showFinancedVehiclesMenu()
    local vehicles = lib.callback.await('qbx_vehicleshop:server:GetVehiclesByName')
    local ownedVehicles = {}

    if vehicles == nil or #vehicles == 0 then return exports.qbx_core:Notify(Lang:t('error.nofinanced'), 'error') end
    for _, v in pairs(vehicles) do
        if v.balance ~= 0 then
            local name = VEHICLES[v.vehicle].name
            local plate = v.plate:upper()
            ownedVehicles[#ownedVehicles + 1] = {
                title = name,
                description = Lang:t('menus.veh_platetxt')..plate,
                icon = 'fa-solid fa-car-side',
                arrow = true,
                onSelect = function()
                    showVehicleFinanceMenu({
                        vehicle = v.vehicle,
                        vehiclePlate = plate,
                        balance = v.balance,
                        paymentsLeft = v.paymentsleft,
                        paymentAmount = v.paymentamount
                    })
                end
            }
        end
    end

    if #ownedVehicles == 0 then
        return exports.qbx_core:Notify(Lang:t('error.nofinanced'), 'error')
    end

    lib.registerContext({
        id = 'ownedVehicles',
        title = Lang:t('menus.owned_vehicles_header'),
        options = ownedVehicles
    })
    lib.showContext('ownedVehicles')
end

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    local citizenId = QBX.PlayerData.citizenid
    TriggerServerEvent('qbx_vehicleshop:server:removePlayer', citizenId)
end)

--- Fetches the name of a vehicle from QB Shared
---@param closestVehicle integer
---@return string
local function getVehName(closestVehicle)
    local vehicle = config.shops[insideShop].showroomVehicles[closestVehicle].vehicle
    return VEHICLES[vehicle].name
end

--- Fetches the price of a vehicle from QB Shared then it formats it into a text
---@param closestVehicle integer
---@return string
local function getVehPrice(closestVehicle)
    local vehicle = config.shops[insideShop].showroomVehicles[closestVehicle].vehicle
    return CommaValue(VEHICLES[vehicle].price)
end

--- Fetches the brand of a vehicle from QB Shared
---@param closestVehicle integer
---@return string
local function getVehBrand(closestVehicle)
    local vehicle = config.shops[insideShop].showroomVehicles[closestVehicle].vehicle
    return VEHICLES[vehicle].brand
end

--- based on which vehicleshop player is in
---@return integer index
local function getClosestShowroomVehicle()
    local pos = GetEntityCoords(cache.ped, true)
    local current = nil
    local dist = nil
    local closestShop = insideShop
    local showroomVehicles = config.shops[closestShop].showroomVehicles
    for id in pairs(showroomVehicles) do
        local dist2 = #(pos - showroomVehicles[id].coords.xyz)
        if not current or dist2 < dist then
            current = id
            dist = dist2
        end
    end
    return current
end

---@param closestShowroomVehicle integer vehicleName
---@param buyVehicle string model
local function openFinance(closestShowroomVehicle, buyVehicle)
    local dialog = lib.inputDialog(VEHICLES[buyVehicle].name:upper()..' '..buyVehicle:upper()..' - $'..getVehPrice(closestShowroomVehicle), {
        {
            type = 'number',
            label = Lang:t('menus.financesubmit_downpayment')..sharedConfig.finance.minimumDown..'%',
        },
        {
            type = 'number',
            label = Lang:t('menus.financesubmit_totalpayment')..sharedConfig.finance.maximumPayments,
        }
    })

    if not dialog then return end

    local downPayment = tonumber(dialog[1])
    local paymentAmount = tonumber(dialog[2])

    if not downPayment or not paymentAmount then return end

    TriggerServerEvent('qbx_vehicleshop:server:financeVehicle', downPayment, paymentAmount, buyVehicle, config.shops[insideShop].vehicleSpawn)
end

--- Opens a menu with list of vehicles based on given category
---@param category string
local function openVehCatsMenu(category)
    local vehMenu = {}
    local closestVehicle = getClosestShowroomVehicle()

    for k, v in pairs(VEHICLES) do
        if VEHICLES[k].category == category then
            if config.vehicles[k] == nil then
                lib.print.debug('Vehicle not found in config.vehicles. Skipping: '..k)
            elseif type(config.vehicles[k].shop) == 'table' then
                for _, shop in pairs(config.vehicles[k].shop) do
                    if shop == insideShop then
                        vehMenu[#vehMenu + 1] = {
                            title = v.brand..' '..v.name,
                            description = Lang:t('menus.veh_price')..lib.math.groupdigits(v.price),
                            serverEvent = 'qbx_vehicleshop:server:swapVehicle',
                            args = {
                                toVehicle = v.model,
                                ClosestVehicle = closestVehicle,
                                ClosestShop = insideShop
                            }
                        }
                    end
                end
            elseif config.vehicles[k].shop == insideShop then
                vehMenu[#vehMenu + 1] = {
                    title = v.brand..' '..v.name,
                    description = Lang:t('menus.veh_price')..lib.math.groupdigits(v.price),
                    serverEvent = 'qbx_vehicleshop:server:swapVehicle',
                    args = {
                        toVehicle = v.model,
                        ClosestVehicle = closestVehicle,
                        ClosestShop = insideShop
                    }
                }
            end
        end
    end

    lib.registerContext({
        id = 'openVehCats',
        title = config.shops[insideShop].categories[category],
        menu = 'vehicleCategories',
        options = vehMenu
    })

    lib.showContext('openVehCats')
end

--- Opens a menu with list of vehicle categories
local function openVehicleCategoryMenu()
    local categoryMenu = {}
    for k, v in pairs(config.shops[insideShop].categories) do
        categoryMenu[#categoryMenu + 1] = {
            title = v,
            arrow = true,
            onSelect = function()
                openVehCatsMenu(k)
            end
        }
    end

    lib.registerContext({
        id = 'vehicleCategories',
        title = Lang:t('menus.categories_header'),
        menu = 'vehicleMenu',
        options = categoryMenu
    })

    lib.showContext('vehicleCategories')
end

---@param closestVehicle integer
local function openCustomFinance(closestVehicle)
    local vehicle = config.shops[insideShop].showroomVehicles[closestVehicle].vehicle
    local dialog = lib.inputDialog(getVehBrand(closestVehicle):upper()..' '..vehicle:upper()..' - $'..getVehPrice(closestVehicle), {
        {
            type = 'number',
            label = Lang:t('menus.financesubmit_downpayment')..sharedConfig.finance.minimumDown..'%',
        },
        {
            type = 'number',
            label = Lang:t('menus.financesubmit_totalpayment')..sharedConfig.finance.maximumPayments,
        },
        {
            type = 'number',
            label = Lang:t('menus.submit_ID'),
        }
    })

    if not dialog then return end

    local downPayment = tonumber(dialog[1])
    local paymentAmount = tonumber(dialog[2])
    local playerid = tonumber(dialog[3])

    if not downPayment or not paymentAmount or not playerid then return end

    TriggerServerEvent('qbx_vehicleshop:server:sellfinanceVehicle', downPayment, paymentAmount, vehicle, playerid, config.shops[insideShop].vehicleSpawn)
end

---prompt client for playerId of another player
---@param vehModel string
---@return number? playerId
local function getPlayerIdInput(vehModel)
    local dialog = lib.inputDialog(VEHICLES[vehModel].name, {
        {
            type = 'number',
            label = Lang:t('menus.submit_ID'),
            placeholder = 1
        }
    })

    if not dialog then return end
    if not dialog[1] then return end

    return tonumber(dialog[1])
end

---@param vehModel string
local function startTestDrive(vehModel)
    local playerId = getPlayerIdInput(vehModel)
    TriggerServerEvent('qbx_vehicleshop:server:customTestDrive', vehModel, playerId)
end

---@param vehModel string
local function sellVehicle(vehModel)
    local playerId = getPlayerIdInput(vehModel)
    TriggerServerEvent('qbx_vehicleshop:server:sellShowroomVehicle', vehModel, playerId)
end

--- Opens the vehicle shop menu
local function openVehicleSellMenu()
    local closestVehicle = getClosestShowroomVehicle()
    local options
    local vehicle = config.shops[insideShop].showroomVehicles[closestVehicle].vehicle
    local location = config.shops[insideShop].vehicleSpawn
    local swapOption = {
        title = Lang:t('menus.swap_header'),
        description = Lang:t('menus.swap_txt'),
        onSelect = openVehicleCategoryMenu,
        arrow = true
    }
    if config.shops[insideShop].type == 'free-use' then
        options = {
            {
                title = Lang:t('menus.test_header'),
                description = Lang:t('menus.freeuse_test_txt'),
                event = 'qbx_vehicleshop:client:testDrive',
                args = {
                    vehicle = vehicle
                }
            }
        }
        print(location)
        if config.enableFreeUseBuy then
            options[#options + 1] = {
                title = Lang:t('menus.freeuse_buy_header'),
                description = Lang:t('menus.freeuse_buy_txt'),
                serverEvent = 'qbx_vehicleshop:server:buyShowroomVehicle',
                args = {
                    buyVehicle = vehicle,
                    location = location
                }
            }
        end

        if config.finance.enable then
            options[#options + 1] = {
                title = Lang:t('menus.finance_header'),
                description = Lang:t('menus.freeuse_finance_txt'),
                onSelect = function()
                    openFinance(closestVehicle, vehicle)
                end
            }
        end

        options[#options + 1] = swapOption
    else
        options = {
            {
                title = Lang:t('menus.test_header'),
                description = Lang:t('menus.managed_test_txt'),
                onSelect = function()
                    startTestDrive(vehicle)
                end,
            },
            {
                title = Lang:t('menus.managed_sell_header'),
                description = Lang:t('menus.managed_sell_txt'),
                onSelect = function()
                    sellVehicle(vehicle)
                end,
            }
        }

        if config.finance.enable then
            options[#options + 1] = {
                title = Lang:t('menus.finance_header'),
                description = Lang:t('menus.managed_finance_txt'),
                onSelect = function()
                    openCustomFinance(closestVehicle)
                end
            }
        end

        options[#options + 1] = swapOption
    end

    lib.registerContext({
        id = 'vehicleMenu',
        title = getVehBrand(closestVehicle):upper()..' '..getVehName(closestVehicle):upper()..' - $'..getVehPrice(closestVehicle),
        options = options
    })
    lib.showContext('vehicleMenu')
end

--- Starts the test drive timer based on time and shop
---@param time number
local function startTestDriveTimer(time)
    local gameTimer = GetGameTimer()
    local timeMs = time * 1000

    CreateThread(function()
        while inTestDrive do
            local currentGameTime = GetGameTimer()
            local secondsLeft = currentGameTime - gameTimer
            if currentGameTime < gameTimer + timeMs and secondsLeft >= timeMs - 50 then
                TriggerServerEvent('qbx_vehicleshop:server:deleteVehicle', testDriveVeh)
                testDriveVeh = 0
                inTestDrive = false
                exports.qbx_core:Notify(Lang:t('general.testdrive_complete'), 'success')
            end
            DrawText2D(Lang:t('general.testdrive_timer')..math.ceil(time - secondsLeft / 1000), vec2(1.0, 1.38), 1.0, 1.0, 0.5)
            Wait(0)
        end
    end)
end

---@param shopName string
---@param entity number vehicle
local function createVehicleTarget(shopName, entity)
    local shop = config.shops[shopName]
    exports.ox_target:addLocalEntity(entity, {
        {
            name = 'vehicleshop:showVehicleOptions',
            icon = 'fas fa-car',
            label = Lang:t('general.vehinteraction'),
            distance = shop.zone.targetDistance,
            onSelect = function()
                openVehicleSellMenu()
            end
        }
    })
end

---@param shopName string
---@param coords vector4
local function createVehicleZone(shopName, coords)
    local shop = config.shops[shopName]
    lib.zones.box({
        coords = coords.xyz,
        size = shop.zone.size,
        rotation = coords.w,
        debug = config.debugPoly,
        onEnter = function()
            local job = config.shops[insideShop].job
            if job and QBX.PlayerData.job.name ~= job then return end
            lib.showTextUI(Lang:t('menus.keypress_vehicleViewMenu'))
        end,
        inside = function()
            local job = config.shops[insideShop].job
            if not IsControlJustPressed(0, 38) or job and QBX.PlayerData.job.name ~= job then return end
            openVehicleSellMenu()
        end,
        onExit = function()
            lib.hideTextUI()
        end
    })
end

--- Creates a shop
---@param shopShape vector3[]
---@param name string
local function createShop(shopShape, name)
    lib.zones.poly({
        name = name,
        points = shopShape,
        thickness = 5,
        debug = config.debugPoly,
        onEnter = function(self)
            insideShop = self.name
        end,
        onExit = function()
            insideShop = nil
        end,
    })
end

---@param model string
---@param coords vector4
---@return number vehicleEntity
local function createShowroomVehicle(model, coords)
    lib.requestModel(model)
    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, coords.w, false, false)
    SetModelAsNoLongerNeeded(model)
    SetVehicleOnGroundProperly(veh)
    SetEntityInvincible(veh, true)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleDoorsLocked(veh, 3)
    FreezeEntityPosition(veh, true)
    SetVehicleNumberPlateText(veh, 'BUY ME')
    return veh
end

--- Initial function to set things up. Creating vehicleshops defined in the config and spawns the sellable vehicles
local shopVehs = {}

local function init()
    CreateThread(function()
        for name, shop in pairs(config.shops) do
            createShop(shop.zone.shape, name)
        end
    end)

    CreateThread(function()
        lib.zones.box({
            coords = config.finance.zone,
            size = vec3(2, 2, 4),
            rotation = 0,
            debug = config.debugPoly,
            onEnter = function()
                lib.showTextUI(Lang:t('menus.keypress_showFinanceMenu'))
            end,
            inside = function()
                if IsControlJustPressed(0, 38) then
                    showFinancedVehiclesMenu()
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end
        })
    end)

    CreateThread(function()
        for shopName in pairs(config.shops) do
            local showroomVehicles = config.shops[shopName].showroomVehicles
            for i = 1, #showroomVehicles do
                local showroomVehicle = showroomVehicles[i]
                local veh = createShowroomVehicle(showroomVehicle.vehicle, showroomVehicle.coords)
                shopVehs[#shopVehs + 1] = veh
                if config.useTarget then
                    createVehicleTarget(shopName, veh)
                else
                    createVehicleZone(shopName, showroomVehicle.coords)
                end
            end
        end
    end)
end

--- Executes once player fully loads in
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    local citizenId = QBX.PlayerData.citizenid
    TriggerServerEvent('qbx_vehicleshop:server:addPlayer', citizenId)
    TriggerServerEvent('qbx_vehicleshop:server:checkFinance')
    init()
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    for i = 1, #shopVehs do
        DeleteEntity(shopVehs[i])
    end
    shopVehs = {}
end)

--- Starts the test drive. If vehicle parameter is not provided then the test drive will start with the closest vehicle to the player.
--- @param args table
RegisterNetEvent('qbx_vehicleshop:client:testDrive', function(args)
    if inTestDrive then
        exports.qbx_core:Notify(Lang:t('error.testdrive_alreadyin'), 'error')
        return
    end

    if not args then return end

    inTestDrive = true
    local testDrive = config.shops[insideShop].testDrive
    local plate = 'TEST'..RandomNumber(4)
    exports['realisticVehicleSystem']:giveVehicleKeysExtra(plate)
    local netId = lib.callback.await('qbx_vehicleshop:server:spawnVehicle', false, args.vehicle, testDrive.spawn, plate)
    testDriveVeh = netId
    exports.qbx_core:Notify(Lang:t('general.testdrive_timenoti'), testDrive.limit, 'inform')
    startTestDriveTimer(testDrive.limit * 60)
end)

--- Swaps the chosen vehicle with another one
---@param data {toVehicle: string, ClosestVehicle: integer, ClosestShop: string}
RegisterNetEvent('qbx_vehicleshop:client:swapVehicle', function(data)
    local shopName = data.ClosestShop
    local dataClosestVehicle = config.shops[shopName].showroomVehicles[data.ClosestVehicle]
    if dataClosestVehicle.vehicle == data.toVehicle then return end

    local closestVehicle = lib.getClosestVehicle(dataClosestVehicle.coords.xyz, 5, false)
    if not closestVehicle then return end

    DeleteEntity(closestVehicle)
    while DoesEntityExist(closestVehicle) do
        Wait(50)
    end

    local veh = createShowroomVehicle(data.toVehicle, dataClosestVehicle.coords)

    dataClosestVehicle.vehicle = data.toVehicle

    if config.useTarget then createVehicleTarget(shopName, veh) end
end)

--- Buys the selected vehicle
---@param vehicle number
---@param plate string
RegisterNetEvent('qbx_vehicleshop:client:buyShowroomVehicle', function(vehicle, plate)
    local tempShop = insideShop -- temp hacky way of setting the shop because it changes after the callback has returned since you are outside the zone
    local netId = lib.callback.await('qbx_vehicleshop:server:spawnVehicle', false, vehicle, config.shops[tempShop].vehicleSpawn, plate)
    local veh = NetToVeh(netId)
    local props = lib.getVehicleProperties(veh)
    props.plate = plate
    TriggerServerEvent('qb-vehicletuning:server:SaveVehicleProps', props)
end)

lib.callback.register('qbx_vehicleshop:client:confirmTrade', function(vehicle, sellAmount)
    local input = lib.inputDialog((Lang:t('general.transfervehicle_confirm')):format(VEHICLES_HASH[vehicle].brand,VEHICLES_HASH[vehicle].name, CommaValue(sellAmount) or 0),{
        {
            type = 'checkbox',
            label = 'Confirm'
        },
    })
    if not input then return false end
    if input[1] == true then return true end
end)

--- Thread to create blips
CreateThread(function()
    for _, v in pairs(config.shops) do
        if v.blip.show then
            local dealer = AddBlipForCoord(v.blip.coords.x, v.blip.coords.y, v.blip.coords.z)
            SetBlipSprite(dealer, v.blip.sprite)
            SetBlipDisplay(dealer, 4)
            SetBlipScale(dealer, 0.70)
            SetBlipAsShortRange(dealer, true)
            SetBlipColour(dealer, v.blip.color)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(v.blip.label)
            EndTextCommandSetBlipName(dealer)
        end
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if GetCurrentResourceName() == resource then
        if LocalPlayer.state.isLoggedIn then init() end
    end
end)
