script_name("Gibson Helper")
script_version("1.1 (Auto Check Norma)")

require "lib.moonloader"
local imgui = require 'mimgui'
local ffi = require 'ffi'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local bit = require 'bit'
local lfs = require 'lfs' -- ДОБАВЛЕНА БИБЛИОТЕКА ДЛЯ РАБОТЫ С ПАПКАМИ

local sampev = require 'lib.samp.events'
local inicfg = require 'inicfg'
local vkeys = require 'vkeys'

-- === БИБЛИОТЕКИ ДЛЯ СПИДХАКА И ПАМЯТИ ===
local samem = require 'SAMemory'
samem.require 'CTrain'
local memory = require 'memory'

-- === БИБЛИОТЕКИ ДЛЯ АИРБРЕЙКА И КЛИКВАРПА ===
local sampfuncs = require 'sampfuncs'
local raknet = require 'samp.raknet'
require 'samp.synchronization'
local Matrix3X3 = require "matrix3x3"
local Vector3D = require "vector3d"

-- === FFI ДЛЯ WALLHACK ===
local getBonePosition = ffi.cast("int (__thiscall*)(void*, float*, int, bool)", 0x5E4280)

local cyrRanges = ffi.new('ImWchar[5]', { 0x0020, 0x00FF, 0x0400, 0x04FF, 0 })

-- === КОНФИГ И СОХРАНЕНИЕ НАСТРОЕК ===
local master_cfg_name = "GibsonHelper_Master.ini"
local default_master = { profile = { current = 1 } }
local master_cfg = inicfg.load(default_master, master_cfg_name)
if not master_cfg then 
    master_cfg = default_master
    inicfg.save(master_cfg, master_cfg_name) 
end
_G.current_profile_id = master_cfg.profile.current
local config_file = "GibsonHelper_profile" .. _G.current_profile_id .. ".ini"

-- Auto-updater config
local script_vers = 1.1
local update_url = "https://raw.githubusercontent.com/YOUR_GITHUB_NAME/GibsonHelper/main/version.json"
local script_url = "https://raw.githubusercontent.com/YOUR_GITHUB_NAME/GibsonHelper/main/GibsonHelper.lua"
local update_path = thisScript().path

local function CheckForUpdates()
    downloadUrlToFile(update_url, getWorkingDirectory() .. "\\config\\gh_version.json", function(id, status, p1, p2)
        if status == 58 then -- dl_status_end
            local f = io.open(getWorkingDirectory() .. "\\config\\gh_version.json", "r")
            if f then
                local json_content = f:read("*a")
                f:close()
                local json = decodeJson(json_content)
                if json and json.version and tonumber(json.version) > script_vers then
                    sampAddChatMessage(string.format("{FF0000}[GibsonHelper]{FFFFFF} Найдено обновление: v%s! Скачивание...", json.version), -1)
                    downloadUrlToFile(script_url, update_path, function(id2, status2, p1_2, p2_2)
                        if status2 == 58 then
                            sampAddChatMessage("{FF0000}[GibsonHelper]{FFFFFF} Обновление завершено. Перезагрузка...", -1)
                            thisScript():reload()
                        end
                    end)
                end
            end
        end
    end)
end
local default_cfg = {
    settings = {
        agm_togphone = false, warn_rvanka = false, warn_cheat_weap = false, auto_alogin = false, alogin_pass = "", theme = 0, auto_open_report = true
    },
    hotkeys = { menu = 0, report = 0, rules = 0, ghetto = 0, invis = 0 },
    templates = {},
    admin = {
        clickwarp = false,
        fast_enter = false,
        gm_car = false,
        speedhack = false,
        sh_limit = 5.386,
        sh_mult = 5.915,
        sh_timestep = 0.032,
        sh_safe_train = true,
        sh_key = 'Left Alt',
        bt_active = false,
        bt_show_id = true,
        bt_color_ped = {1.0, 0.0, 0.0},
        bt_color_car = {0.0, 1.0, 0.0},
        bt_color_obj = {1.0, 1.0, 0.0},
        bt_thickness = 2.0,
        bt_time = 2.0,
        airbreak = false,
        ab_speed_player = 0.76, ab_speed_vehicle = 1.5, ab_speed_passenger = 0.2,
        ab_sync_player = 1.8, ab_sync_vehicle = 1.2, ab_sync_passenger = 0.5,
        invis = false,
        wh_state = false,
        wh_mode = 0,
        wh_name_height = 1.1,
        wh_bone_thick = 1.0,
        wh_distance = 300.0,
        nobike_active = false
    }
}
local main_cfg = inicfg.load(default_cfg, config_file)

local report_tpls = {}
if main_cfg.templates and main_cfg.templates.count then
    for i = 1, tonumber(main_cfg.templates.count) do
        table.insert(report_tpls, { name = u8(main_cfg.templates["name_"..i] or ""), text = u8(main_cfg.templates["text_"..i] or "") })
    end
else
    report_tpls = { {name = "Приятной игры", text = "Уважаемый игрок, желаем вам приятной игры!"}, {name = "Уточните", text = "Уважаемый игрок, уточните вашу жалобу!"} }
end

-- === ТАБЛИЦА ПРАВИЛ ===
local rules_list = {
    { file = "Правила сервера и выдачи наказания", ui = "Правила сервера и выдачи наказания" },
    { file = "Правила Администрации", ui = "Правила Администрации" },
    { file = "Правила Использования aad и o", ui = "Правила Использования \"/aad\" и \"/о\"" },
    { file = "Cистема Выдачи Наказаний", ui = "Cистема Выдачи Наказаний" },
    { file = "Правила проведения захвата территорий", ui = "Правила проведения захвата территорий." },
    { file = "Правила проведения стрел", ui = "Правила проведения стрел." },
    { file = "Правила проведения захвата", ui = "Правила проведения захвата." },
    { file = "Общие правила для Министерства Юстиции", ui = "Общие правила для Министерства Юстиции." }
}
local rules_content = {}

-- === ПЕРЕМЕННЫЕ СОСТОЯНИЯ ===
local st = {
    renderWindow = imgui.new.bool(false),
    reportWindow = imgui.new.bool(false),
    activeTab    = imgui.new.int(1),
    report_queue = {},
    active_report = nil,
    tracers = {}, 
    custom_reply_buf = imgui.new.char[256](""),
    search_rules_buf = imgui.new.char[256](""), -- Буфер поиска правил

    auto_give_chat_idx = imgui.new.int(0),
    auto_give_word_buf = imgui.new.char[64](""),
    auto_give_prize_idx = imgui.new.int(0),
    auto_give_count_buf = imgui.new.char[32](""),

    auto_give_active = false,
    auto_give_word_saved = "",
    auto_give_chat_saved = "",
    auto_give_prize_idx_saved = 0,
    auto_give_count_saved = "",
    pending_object_dialog = nil,

    -- Переменные для мероприятий
    mp_chat_idx = imgui.new.int(0),
    mp_list_idx = imgui.new.int(0),
    mp_prize_buf = imgui.new.char[128](""),

    -- Переменные для отборов
    otbor_list_idx = imgui.new.int(0),

    -- Переменные для выдачи оружия
    givegun_weapon_idx = imgui.new.int(2),
    givegun_ammo_buf = imgui.new.char[32]("100"),

    setskin_id = imgui.new.int(0),
    setskin_self = imgui.new.bool(true),
    setskin_id_buf = imgui.new.char[32](""),

    -- Переменные для спавна транспорта
    spawnveh_idx = imgui.new.int(0),
    spawnveh_color1 = imgui.new.char[16]("0"),
    spawnveh_color2 = imgui.new.char[16]("0"),
    spawnveh_turbo = imgui.new.bool(false),
    spawnveh_temp = imgui.new.bool(false),

    -- Переменные для Авто чека нормы
    norm_input_buf = imgui.new.char[8192](""),
    norm_output_buf = imgui.new.char[8192](""),
    norm_is_checking = false,
    norm_progress = imgui.new.int(0),
    norm_total = imgui.new.int(0),
    norm_current_result = nil,

    cfg_agm_togphone     = imgui.new.bool(main_cfg.settings.agm_togphone),
    cfg_warn_rvanka      = imgui.new.bool(main_cfg.settings.warn_rvanka),
    cfg_warn_cheat_weap  = imgui.new.bool(main_cfg.settings.warn_cheat_weap),
    cfg_auto_alogin      = imgui.new.bool(main_cfg.settings.auto_alogin),
    cfg_auto_open_report = imgui.new.bool(main_cfg.settings.auto_open_report),
    cfg_alogin_pass      = imgui.new.char[256](tostring(main_cfg.settings.alogin_pass or "")),
    current_theme        = imgui.new.int(main_cfg.settings.theme or 0),

    hk_menu   = imgui.new.int(main_cfg.hotkeys.menu),
    hk_report = imgui.new.int(main_cfg.hotkeys.report),
    hk_rules  = imgui.new.int(main_cfg.hotkeys.rules),
    hk_ghetto = imgui.new.int(main_cfg.hotkeys.ghetto),
    hk_invis  = imgui.new.int(main_cfg.hotkeys.invis),

    cfg_adm_clickwarp      = imgui.new.bool(main_cfg.admin.clickwarp),
    cfg_adm_fast_enter     = imgui.new.bool(main_cfg.admin.fast_enter),
    cfg_adm_gm_car         = imgui.new.bool(main_cfg.admin.gm_car),
    cfg_adm_speedhack      = imgui.new.bool(main_cfg.admin.speedhack),
    cfg_adm_invis          = imgui.new.bool(main_cfg.admin.invis),

    sh_limit               = imgui.new.float(main_cfg.admin.sh_limit or 5.386),
    sh_mult                = imgui.new.float(main_cfg.admin.sh_mult or 5.915),
    sh_timestep            = imgui.new.float(main_cfg.admin.sh_timestep or 0.032),
    sh_safe_train          = imgui.new.bool(main_cfg.admin.sh_safe_train ~= false),
    sh_key                 = imgui.new.char[64](tostring(main_cfg.admin.sh_key or 'Left Alt')),

    cfg_bt_active          = imgui.new.bool(main_cfg.admin.bt_active),
    cfg_bt_show_id         = imgui.new.bool(main_cfg.admin.bt_show_id ~= false),
    cfg_bt_color_ped       = ffi.new('float[3]', {main_cfg.admin.bt_color_ped[1] or 1.0, main_cfg.admin.bt_color_ped[2] or 0.0, main_cfg.admin.bt_color_ped[3] or 0.0}),
    cfg_bt_color_car       = ffi.new('float[3]', {main_cfg.admin.bt_color_car[1] or 0.0, main_cfg.admin.bt_color_car[2] or 1.0, main_cfg.admin.bt_color_car[3] or 0.0}),
    cfg_bt_color_obj       = ffi.new('float[3]', {main_cfg.admin.bt_color_obj[1] or 1.0, main_cfg.admin.bt_color_obj[2] or 1.0, main_cfg.admin.bt_color_obj[3] or 0.0}),
    cfg_bt_thickness       = imgui.new.float(main_cfg.admin.bt_thickness or 2.0),
    cfg_bt_time            = imgui.new.float(main_cfg.admin.bt_time or 2.0),

    cfg_ab_state           = imgui.new.bool(main_cfg.admin.airbreak),
    cfg_ab_speed_player    = imgui.new.float(main_cfg.admin.ab_speed_player),
    cfg_ab_speed_vehicle   = imgui.new.float(main_cfg.admin.ab_speed_vehicle),
    cfg_ab_speed_passenger = imgui.new.float(main_cfg.admin.ab_speed_passenger),
    cfg_ab_sync_player     = imgui.new.float(main_cfg.admin.ab_sync_player),
    cfg_ab_sync_vehicle    = imgui.new.float(main_cfg.admin.ab_sync_vehicle),
    cfg_ab_sync_passenger  = imgui.new.float(main_cfg.admin.ab_sync_passenger),

    cfg_wh_state           = imgui.new.bool(main_cfg.admin.wh_state),
    cfg_wh_mode            = imgui.new.int(main_cfg.admin.wh_mode),
    cfg_wh_name_height     = imgui.new.float(main_cfg.admin.wh_name_height or 1.1),
    cfg_wh_bone_thick      = imgui.new.float(main_cfg.admin.wh_bone_thick or 1.0),
    cfg_wh_distance        = imgui.new.float(main_cfg.admin.wh_distance or 300.0),

    nb_active              = imgui.new.bool(main_cfg.admin.nobike_active),

    ab_active = false,
    invis_active = false,
    airBrkCoords = {0, 0, 0},
    current_binding = nil,
    last_gm_car = 0,
    
    cw_cursorEnabled = false,
    cw_pointMarker = nil
}

local prizes = {
    "Уровень", "Законопослушность", "Материалы", "Убийства",
    "Номер телефона", "EXP", "Деньги в банке", "Деньги на мобиле",
    "Наличные деньги", "Аптечки", "Член орг.", "Бокс", "Kung-Fu", "KickBox",
    "Наркозависимость", "Наркотики",
    "Шляпа курицы", "Огонек на голову", "Мигалка на голову", "Черная маска",
    "Бандана №1", "Бандана №2", "Бандана №3", "Бандана №4", "Бандана №5",
    "Маска дракона", "Лазер на голову", "Комплект всемогущий", "Попугай на плечо",
    "Яркий свет", "Большой M4 в руку", "Пенис", "Костюм попугая", "Удалить все объекты"
}

local mp_list = {
    "Король Дигла", "Русская Рулетка", "Поливалка", "Дерби",
    "Снайпер", "Paint-Ball", "Бой на Катанах"
}

local leader_list = {
    "LSPD", "ФБР", "Army LS", "Больница ЛС", "LCN", "Yakuza", "Мэрия",
    "Ballas", "Vagos", "Russia Mafia", "Grove", "Радиоцентр", "Aztec",
    "Rifa", "Xitman", "SWAT", "АП", "RCPD", "Outlaws MC", "Верховный Суд"
}

local weapon_list = {
    {name = "Brass Knuckles", id = 1},
    {name = "Golf Club", id = 2},
    {name = "Nightstick", id = 3},
    {name = "Knife", id = 4},
    {name = "Baseball Bat", id = 5},
    {name = "Shovel", id = 6},
    {name = "Pool Cue", id = 7},
    {name = "Katana", id = 8},
    {name = "Chainsaw", id = 9},
    {name = "Grenade", id = 16},
    {name = "Molotov", id = 18},
    {name = "Colt 45", id = 22},
    {name = "Silenced Pistol", id = 23},
    {name = "Deagle", id = 24},
    {name = "Shotgun", id = 25},
    {name = "Sawn-off", id = 26},
    {name = "Combat Shotgun", id = 27},
    {name = "Micro Uzi", id = 28},
    {name = "MP5", id = 29},
    {name = "AK-47", id = 30},
    {name = "M4", id = 31},
    {name = "Tec-9", id = 32},
    {name = "Country Rifle", id = 33},
    {name = "Sniper Rifle", id = 34},
    {name = "RPG", id = 35},
    {name = "Flame Thrower", id = 37},
    {name = "Minigun", id = 38}
}

local vehicle_list = {
    {name = "Landstalker", id = 400},
{name = "Bravura", id = 401},
{name = "Buffalo", id = 402},
{name = "Linerunner", id = 403},
{name = "Pereniel", id = 404},
{name = "Sentinel", id = 405},
{name = "Dumper", id = 406},
{name = "Firetruck", id = 407},
{name = "Trashmaster", id = 408},
{name = "Stretch", id = 409},
{name = "Manana", id = 410},
{name = "Infernus", id = 411},
{name = "Voodoo", id = 412},
{name = "Pony", id = 413},
{name = "Mule", id = 414},
{name = "Cheetah", id = 415},
{name = "Ambulance", id = 416},
{name = "Leviathan", id = 417},
{name = "Moonbeam", id = 418},
{name = "Esperanto", id = 419},
{name = "Taxi", id = 420},
{name = "Washington", id = 421},
{name = "Bobcat", id = 422},
{name = "Mr Whoopee", id = 423},
{name = "BF Injection", id = 424},
{name = "Hunter", id = 425},
{name = "Premier", id = 426},
{name = "Enforcer", id = 427},
{name = "Securicar", id = 428},
{name = "Banshee", id = 429},
{name = "Predator", id = 430},
{name = "Bus", id = 431},
{name = "Rhino", id = 432},
{name = "Barracks OL", id = 433},
{name = "Hotknife", id = 434},
{name = "Article Trailer", id = 435},
{name = "Previon", id = 436},
{name = "Coach", id = 437},
{name = "Cabbie", id = 438},
{name = "Stallion", id = 439},
{name = "Rumpo", id = 440},
{name = "RC Bandit", id = 441},
{name = "Romero", id = 442},
{name = "Packer", id = 443},
{name = "Monster Truck", id = 444},
{name = "Admiral", id = 445},
{name = "Squalo", id = 446},
{name = "Seasparrow", id = 447},
{name = "Pizzaboy", id = 448},
{name = "Tram", id = 449},
{name = "Article Trailer 2", id = 450},
{name = "Turismo", id = 451},
{name = "Speeder", id = 452},
{name = "Reefer", id = 453},
{name = "Tropic", id = 454},
{name = "Flatbed", id = 455},
{name = "Yankee", id = 456},
{name = "Caddy", id = 457},
{name = "Solair", id = 458},
{name = "Berkley's RC Van", id = 459},
{name = "Skimmer", id = 460},
{name = "PCJ-600", id = 461},
{name = "Faggio", id = 462},
{name = "Freeway", id = 463},
{name = "RC Baron", id = 464},
{name = "RC Raider", id = 465},
{name = "Glendale", id = 466},
{name = "Oceanic", id = 467},
{name = "Sanchez", id = 468},
{name = "Sparrow", id = 469},
{name = "Patriot", id = 470},
{name = "Quad", id = 471},
{name = "Coastguard", id = 472},
{name = "Dinghy", id = 473},
{name = "Hermes", id = 474},
{name = "Sabre", id = 475},
{name = "Rustler", id = 476},
{name = "ZR-350", id = 477},
{name = "Walton", id = 478},
{name = "Regina", id = 479},
{name = "Comet", id = 480},
{name = "BMX", id = 481},
{name = "Burrito", id = 482},
{name = "Camper", id = 483},
{name = "Marquis", id = 484},
{name = "Baggage", id = 485},
{name = "Dozer", id = 486},
{name = "Maverick", id = 487},
{name = "News Chopper", id = 488},
{name = "Rancher", id = 489},
{name = "FBI Rancher", id = 490},
{name = "Virgo", id = 491},
{name = "Greenwood", id = 492},
{name = "Jetmax", id = 493},
{name = "Hotring Racer", id = 494},
{name = "Sandking", id = 495},
{name = "Blista Compact", id = 496},
{name = "Police Maverick", id = 497},
{name = "Boxville", id = 498},
{name = "Benson", id = 499},
{name = "Mesa", id = 500},
{name = "RC Goblin", id = 501},
{name = "Hotring Racer A", id = 502},
{name = "Hotring Racer B", id = 503},
{name = "Bloodring Banger", id = 504},
{name = "Rancher", id = 505},
{name = "Super GT", id = 506},
{name = "Elegant", id = 507},
{name = "Journey", id = 508},
{name = "Bike", id = 509},
{name = "Mountain Bike", id = 510},
{name = "Beagle", id = 511},
{name = "Cropduster", id = 512},
{name = "Stuntplane", id = 513},
{name = "Tanker", id = 514},
{name = "Roadtrain", id = 515},
{name = "Nebula", id = 516},
{name = "Majestic", id = 517},
{name = "Buccaneer", id = 518},
{name = "Shamal", id = 519},
{name = "Hydra", id = 520},
{name = "FCR-900", id = 521},
{name = "NRG-500", id = 522},
{name = "HPV1000", id = 523},
{name = "Cement Truck", id = 524},
{name = "Towtruck", id = 525},
{name = "Fortune", id = 526},
{name = "Cadrona", id = 527},
{name = "FBI Truck", id = 528},
{name = "Willard", id = 529},
{name = "Forklift", id = 530},
{name = "Tractor", id = 531},
{name = "Combine Harvester", id = 532},
{name = "Feltzer", id = 533},
{name = "Remington", id = 534},
{name = "Slamvan", id = 535},
{name = "Blade", id = 536},
{name = "Freight", id = 537},
{name = "Streak", id = 538},
{name = "Vortex", id = 539},
{name = "Vincent", id = 540},
{name = "Bullet", id = 541},
{name = "Clover", id = 542},
{name = "Sadler", id = 543},
{name = "Firetruck LA", id = 544},
{name = "Hustler", id = 545},
{name = "Intruder", id = 546},
{name = "Primo", id = 547},
{name = "Cargobob", id = 548},
{name = "Tampa", id = 549},
{name = "Sunrise", id = 550},
{name = "Merit", id = 551},
{name = "Utility Van", id = 552},
{name = "Nevada", id = 553},
{name = "Yosemite", id = 554},
{name = "Windsor", id = 555},
{name = "Monster A", id = 556},
{name = "Monster B", id = 557},
{name = "Uranus", id = 558},
{name = "Jester", id = 559},
{name = "Sultan", id = 560},
{name = "Stratum", id = 561},
{name = "Elegy", id = 562},
{name = "Raindance", id = 563},
{name = "RC Tiger", id = 564},
{name = "Flash", id = 565},
{name = "Tahoma", id = 566},
{name = "Savanna", id = 567},
{name = "Bandito", id = 568},
{name = "Freight Flat", id = 569},
{name = "Streak Carriage", id = 570},
{name = "Kart", id = 571},
{name = "Mower", id = 572},
{name = "Dune", id = 573},
{name = "Sweeper", id = 574},
{name = "Broadway", id = 575},
{name = "Tornado", id = 576},
{name = "AT-400", id = 577},
{name = "DFT-30", id = 578},
{name = "Huntley", id = 579},
{name = "Stafford", id = 580},
{name = "BF-400", id = 581},
{name = "Newsvan", id = 582},
{name = "Tug", id = 583},
{name = "Petrotrailer", id = 584},
{name = "Emperor", id = 585},
{name = "Wayfarer", id = 586},
{name = "Euros", id = 587},
{name = "Hotdog", id = 588},
{name = "Club", id = 589},
{name = "Freight Carriage", id = 590},
{name = "Trailer 3", id = 591},
{name = "Andromada", id = 592},
{name = "Dodo", id = 593},
{name = "RC Cam", id = 594},
{name = "Launch", id = 595},
{name = "Police Car (LSPD)", id = 596},
{name = "Police Car (SFPD)", id = 597},
{name = "Police Car (LVPD)", id = 598},
{name = "Police Ranger", id = 599},
{name = "Picador", id = 600},
{name = "S.W.A.T.", id = 601},
{name = "Alpha", id = 602},
{name = "Phoenix", id = 603},
{name = "Glendale (damaged)", id = 604},
{name = "Sadler (damaged)", id = 605},
{name = "Baggage Trailer A", id = 606},
{name = "Baggage Trailer B", id = 607},
{name = "Tug Stairs Trailer", id = 608},
{name = "Boxville", id = 609},
{name = "Farm Plow", id = 610}
}

local skin_categories = {
    {
        name = "Главные персонажи / Story Characters",
        color = imgui.ImVec4(1.0, 0.8, 0.2, 1.0), -- Желто-оранжевый
        skins = {
            {id=0, name="Carl 'CJ' Johnson"}, {id=1, name="The Truth"}, {id=2, name="Maccer"}, {id=3, name="Andre"}, {id=4, name="Big Bear (Thin)"}, {id=5, name="Big Bear (Big)"}, {id=6, name="Emmet"}, {id=7, name="Taxi/Train Driver"}, {id=8, name="Janitor"}, {id=9, name="Normal Ped (F)"}, {id=10, name="Old Woman"}, {id=11, name="Casino Croupier (F)"}, {id=12, name="Rich Woman"}, {id=13, name="Street Girl"}, {id=14, name="Normal Ped"}, {id=15, name="Mr. Whittaker"}, {id=16, name="Airport Worker"}, {id=17, name="Businessman"}, {id=18, name="Beach Visitor"}, {id=19, name="DJ"}, {id=20, name="Rich Guy"}, {id=21, name="Normal Ped"}, {id=22, name="Normal Ped"}, {id=23, name="BMXer"}, {id=24, name="Madd Dogg Bodyguard"}, {id=25, name="Madd Dogg Bodyguard 2"}, {id=26, name="Backpacker"}, {id=27, name="Construction Worker"}, {id=28, name="Drug Dealer"}, {id=29, name="Drug Dealer"}, {id=30, name="Drug Dealer"}, {id=31, name="Farm Inhabitant (F)"}, {id=32, name="Farm Inhabitant"}, {id=33, name="Farm Inhabitant"}, {id=34, name="Farm Inhabitant"}, {id=35, name="Gardener"}, {id=36, name="Golfer"}, {id=37, name="Golfer"}, {id=38, name="Normal Ped (F)"}, {id=39, name="Normal Ped (F)"}, {id=40, name="Normal Ped (F)"}, {id=41, name="Normal Ped (F)"}, {id=42, name="Jethro"}, {id=43, name="Normal Ped"}, {id=44, name="Normal Ped"}, {id=45, name="Beach Visitor"}, {id=46, name="Normal Ped"}, {id=47, name="Normal Ped"}, {id=48, name="Normal Ped"}, {id=49, name="Da Nang Snakehead"}, {id=50, name="Mechanic"}, {id=51, name="Mountain Biker"}, {id=52, name="Mountain Biker"}, {id=53, name="Normal Ped (F)"}, {id=54, name="Normal Ped (F)"}, {id=55, name="Normal Ped (F)"}, {id=56, name="Normal Ped (F)"}, {id=57, name="Oriental Ped"}, {id=58, name="Oriental Ped"}, {id=59, name="Normal Ped"}, {id=60, name="Normal Ped"}, {id=61, name="Pilot"}, {id=62, name="Colonel Fuhrberger"}, {id=63, name="Prostitute"}, {id=64, name="Prostitute"}, {id=65, name="Kendl Johnson"}, {id=66, name="Pool Player"}, {id=67, name="Pool Player"}, {id=68, name="Priest"}, {id=69, name="Normal Ped (F)"}, {id=70, name="Scientist"}, {id=71, name="Security Guard"}, {id=72, name="Hippy"}, {id=73, name="Hippy"}, {id=74, name="Unknown"}, {id=75, name="Prostitute"}, {id=76, name="Stewardess"}, {id=77, name="Homeless (F)"}, {id=78, name="Homeless"}, {id=79, name="Homeless"}, {id=80, name="Boxer"}, {id=81, name="Boxer"}, {id=82, name="Black Elvis"}, {id=83, name="White Elvis"}, {id=84, name="Blue Elvis"}, {id=85, name="Prostitute"}, {id=86, name="Ryder (Masked)"}, {id=87, name="Stripper"}, {id=88, name="Normal Ped (F)"}, {id=89, name="Normal Ped (F)"}, {id=90, name="Jogger (F)"}, {id=91, name="Rich Woman"}, {id=92, name="Rollerskater (F)"}, {id=93, name="Normal Ped (F)"}, {id=94, name="Normal Ped"}, {id=95, name="Normal Ped"}, {id=96, name="Jogger"}, {id=97, name="Lifeguard"}, {id=98, name="Normal Ped"}, {id=99, name="Rollerskater"}, {id=100, name="Biker"}, {id=101, name="Normal Ped"}
        }
    },
    {
        name = "Банды / Gangs",
        color = imgui.ImVec4(0.2, 0.8, 0.2, 1.0), -- Зеленый
        skins = {
            {id=102, name="Balla 1"}, {id=103, name="Balla 2"}, {id=104, name="Balla 3"}, {id=105, name="Grove Street 1"}, {id=106, name="Grove Street 2"}, {id=107, name="Grove Street 3"}, {id=108, name="Los Santos Vagos 1"}, {id=109, name="Los Santos Vagos 2"}, {id=110, name="Los Santos Vagos 3"}, {id=111, name="Russian Mafia"}, {id=112, name="Russian Mafia"}, {id=113, name="Russian Mafia Boss"}, {id=114, name="Varios Los Aztecas 1"}, {id=115, name="Varios Los Aztecas 2"}, {id=116, name="Varios Los Aztecas 3"}, {id=117, name="Triad"}, {id=118, name="Triad"}, {id=119, name="Johnny Sindacco"}, {id=120, name="Triad Boss"}, {id=121, name="Da Nang Boy 1"}, {id=122, name="Da Nang Boy 2"}, {id=123, name="Da Nang Boy 3"}, {id=124, name="The Mafia 1"}, {id=125, name="The Mafia 2"}, {id=126, name="The Mafia 3"}, {id=127, name="The Mafia 4"}, {id=173, name="San Fierro Rifa 1"}, {id=174, name="San Fierro Rifa 2"}, {id=175, name="San Fierro Rifa 3"}
        }
    },
    {
        name = "Обычные NPC / Civilians",
        color = imgui.ImVec4(0.7, 0.7, 0.7, 1.0), -- Светло-серый
        skins = {
            {id=128, name="Farm Inhabitant"}, {id=129, name="Farm Inhabitant (F)"}, {id=130, name="Farm Inhabitant (F)"}, {id=131, name="Farm Inhabitant (F)"}, {id=132, name="Farm Inhabitant"}, {id=133, name="Farm Inhabitant"}, {id=134, name="Homeless"}, {id=135, name="Homeless"}, {id=136, name="Normal Ped"}, {id=137, name="Homeless"}, {id=138, name="Beach Visitor (F)"}, {id=139, name="Beach Visitor (F)"}, {id=140, name="Beach Visitor (F)"}, {id=141, name="Businesswoman"}, {id=142, name="Taxi Driver"}, {id=143, name="Crack Maker"}, {id=144, name="Crack Maker"}, {id=145, name="Crack Maker (F)"}, {id=146, name="Crack Maker"}, {id=147, name="Businessman"}, {id=148, name="Businesswoman"}, {id=149, name="Big Smoke (Armored)"}, {id=150, name="Businesswoman"}, {id=151, name="Normal Ped (F)"}, {id=152, name="Prostitute"}, {id=153, name="Construction Worker"}, {id=154, name="Beach Visitor"}, {id=155, name="Pizza Worker"}, {id=156, name="Barber"}, {id=157, name="Hillbilly (F)"}, {id=158, name="Farmer"}, {id=159, name="Hillbilly"}, {id=160, name="Hillbilly"}, {id=161, name="Farmer"}, {id=162, name="Hillbilly"}, {id=163, name="Bouncer"}, {id=164, name="Bouncer"}, {id=165, name="MIB Agent"}, {id=166, name="MIB Agent"}, {id=167, name="Cluckin Bell Worker"}, {id=168, name="Hotdog Vendor"}, {id=169, name="Normal Ped (F)"}, {id=170, name="Normal Ped"}, {id=171, name="Blackjack Dealer"}, {id=172, name="Casino Croupier (F)"}, {id=176, name="Barber"}, {id=177, name="Barber"}, {id=178, name="Whore"}, {id=179, name="Ammunation Salesman"}, {id=180, name="Tattoo Artist"}, {id=181, name="Punk"}, {id=182, name="Cab Driver"}, {id=183, name="Normal Ped"}, {id=184, name="Normal Ped"}, {id=185, name="Normal Ped"}, {id=186, name="Normal Ped"}, {id=187, name="Oriental Businessman"}, {id=188, name="Normal Ped"}, {id=189, name="Valet"}, {id=196, name="Farm Inhabitant (F)"}, {id=197, name="Hillbilly (F)"}, {id=198, name="Farm Inhabitant (F)"}, {id=199, name="Farm Inhabitant (F)"}, {id=200, name="Hillbilly"}, {id=201, name="Farmer (F)"}, {id=202, name="Farmer"}, {id=203, name="Karate Teacher"}, {id=204, name="Karate Teacher"}, {id=205, name="Burger Shot Cashier"}, {id=206, name="Cab Driver"}, {id=207, name="Prostitute"}, {id=209, name="Noodle Vendor"}, {id=210, name="Boating Instructor"}, {id=211, name="Clothes Shop Staff (F)"}, {id=212, name="Homeless"}, {id=213, name="Weird Old Man"}, {id=214, name="Waitress (Maria)"}, {id=215, name="Normal Ped (F)"}, {id=216, name="Normal Ped (F)"}, {id=218, name="Normal Ped (F)"}, {id=219, name="Rich Woman"}, {id=220, name="Cab Driver"}, {id=221, name="Normal Ped"}, {id=222, name="Normal Ped"}, {id=223, name="Normal Ped"}, {id=224, name="Normal Ped (F)"}, {id=225, name="Normal Ped (F)"}, {id=226, name="Normal Ped (F)"}, {id=227, name="Oriental Businessman"}, {id=228, name="Oriental Ped"}, {id=229, name="Oriental Ped"}, {id=231, name="Normal Ped (F)"}, {id=232, name="Normal Ped (F)"}, {id=233, name="Normal Ped (F)"}, {id=234, name="Cab Driver"}, {id=235, name="Normal Ped"}, {id=236, name="Normal Ped"}, {id=237, name="Prostitute"}, {id=238, name="Prostitute"}, {id=239, name="Homeless"}, {id=241, name="Afro-American"}, {id=242, name="Mexican"}, {id=243, name="Prostitute"}, {id=244, name="Stripper"}, {id=245, name="Prostitute"}, {id=246, name="Stripper"}, {id=247, name="Biker"}, {id=248, name="Biker"}, {id=249, name="Pimp"}, {id=250, name="Normal Ped"}, {id=251, name="Lifeguard (F)"}, {id=252, name="Naked Valet"}, {id=253, name="Bus Driver"}, {id=254, name="Biker Drug Dealer"}, {id=255, name="Chauffeur"}, {id=256, name="Stripper"}, {id=257, name="Stripper"}, {id=258, name="Heckler"}, {id=259, name="Heckler"}, {id=260, name="Construction Worker"}, {id=261, name="Cab Driver"}, {id=262, name="Cab Driver"}, {id=263, name="Normal Ped (F)"}, {id=264, name="Clown (Ice Cream Van)"}
        }
    },
    {
        name = "Девушки CJ / CJ's Girlfriends",
        color = imgui.ImVec4(1.0, 0.4, 0.7, 1.0), -- Розовый
        skins = {
            {id=190, name="Barbara Schternvart"}, {id=191, name="Helena Wankstein"}, {id=192, name="Michelle Cannes"}, {id=193, name="Katie Zhan"}, {id=194, name="Millie Perkins"}, {id=195, name="Denise Robinson"}
        }
    },
    {
        name = "Известные персонажи / Named Characters",
        color = imgui.ImVec4(0.9, 0.5, 0.1, 1.0), -- Оранжевый
        skins = {
            {id=208, name="Su Xi Mu (Suzie)"}, {id=217, name="Clothes Shop Staff"}, {id=230, name="Homeless"}, {id=240, name="The D.A."}, {id=265, name="Frank Tenpenny"}, {id=266, name="Eddie Pulaski"}, {id=267, name="Jimmy Hernandez"}, {id=268, name="Dwayne"}, {id=269, name="Big Smoke"}, {id=270, name="Sweet Johnson"}, {id=271, name="Ryder"}, {id=272, name="Mafia Boss (Forelli)"}, {id=273, name="T-Bone Mendez"}, {id=289, name="Zero"}, {id=290, name="Ken Rosenberg"}, {id=291, name="Kent Paul"}, {id=292, name="Cesar Vialpando"}, {id=293, name="OG Loc"}, {id=294, name="Wu Zi Mu (Woozie)"}, {id=295, name="Mike Toreno"}, {id=296, name="Jizzy B."}, {id=297, name="Madd Dogg"}, {id=298, name="Catalina"}, {id=299, name="Claude Speed"}
        }
    },
    {
        name = "Медики / Paramedics",
        color = imgui.ImVec4(1.0, 0.3, 0.3, 1.0), -- Красный (коралловый)
        skins = {
            {id=274, name="Paramedic (Los Santos)"}, {id=275, name="Paramedic (Las Venturas)"}, {id=276, name="Paramedic (San Fierro)"}
        }
    },
    {
        name = "Пожарные / Firefighters",
        color = imgui.ImVec4(1.0, 0.6, 0.2, 1.0), -- Ярко-оранжевый
        skins = {
            {id=277, name="Firefighter (Los Santos)"}, {id=278, name="Firefighter (Las Venturas)"}, {id=279, name="Firefighter (San Fierro)"}
        }
    },
    {
        name = "Полиция / Law Enforcement",
        color = imgui.ImVec4(0.3, 0.6, 1.0, 1.0), -- Синий
        skins = {
            {id=280, name="LSPD Officer"}, {id=281, name="SFPD Officer"}, {id=282, name="LVPD Officer"}, {id=283, name="County Sheriff"}, {id=284, name="LSPD Motorbike Cop"}, {id=285, name="SWAT"}, {id=286, name="Federal Agent (FBI)"}, {id=287, name="Army"}, {id=288, name="Desert Sheriff"}
        }
    },
    {
        name = "Добавлены в SA-MP 0.3.7 RC3",
        color = imgui.ImVec4(0.7, 0.4, 0.9, 1.0), -- Фиолетовый
        skins = {
            {id=300, name="LSPD (No Holster)"}, {id=301, name="SFPD (No Holster)"}, {id=302, name="LVPD (No Holster)"}, {id=303, name="LSPD (No Uniform) 1"}, {id=304, name="LSPD (No Uniform) 2"}, {id=305, name="LVPD (No Uniform)"}, {id=306, name="LSPD Officer (F)"}, {id=307, name="SFPD Officer (F)"}, {id=308, name="SF Paramedic (F)"}, {id=309, name="LVPD Officer (F)"}, {id=310, name="County Sheriff (No Hat)"}, {id=311, name="Desert Sheriff (No Hat)"}
        }
    }
}

-- Исключаем крашащие SA-MP скины автоматически при запуске
local invalid_skins = {[3]=true,[4]=true,[5]=true,[42]=true,[65]=true,[74]=true,[86]=true,[119]=true,[149]=true,[208]=true,[268]=true,[273]=true,[289]=true}
for _, cat in ipairs(skin_categories) do
    local safe_skins = {}
    for _, s in ipairs(cat.skins) do
        if not invalid_skins[s.id] then table.insert(safe_skins, s) end
    end
    cat.skins = safe_skins
end

local cw_font = nil
local cw_font2 = nil
local tracer_font = nil
local nameTag = false
local NTdist, NTwalls, NTshow

-- === ИНИЦИАЛИЗАЦИЯ ПРАВИЛ ИЗ ФАЙЛОВ ===
local function initRules()
    local dir = getWorkingDirectory() .. "\\GibsonHelper"
    if not lfs.attributes(dir, "mode") then
        lfs.mkdir(dir)
    end
    for _, rule in ipairs(rules_list) do
        local filepath = dir .. "\\" .. u8:decode(rule.file) .. ".txt"
        local f = io.open(filepath, "r")
        if not f then
            f = io.open(filepath, "w")
            if f then
                f:write(u8:decode("Тут будут правила: " .. rule.ui))
                f:close()
            end
            rules_content[rule.file] = "Тут будут правила: " .. rule.ui
        else
            rules_content[rule.file] = u8(f:read("*a"))
            f:close()
        end
    end
end

-- === ФУНКЦИИ WALLHACK ===
function getBodyPartCoordinates(id, handle)
    local pedptr = getCharPointer(handle)
    local vec = ffi.new("float[3]")
    getBonePosition(ffi.cast("void*", pedptr), vec, id, true)
    return vec[0], vec[1], vec[2]
end

function nameTagOn()
    local pStSet = sampGetServerSettingsPtr()
    NTdist = memory.getfloat(pStSet + 39)
    NTwalls = memory.getint8(pStSet + 47)
    NTshow = memory.getint8(pStSet + 56)
    memory.setfloat(pStSet + 39, 1488.0)
    memory.setint8(pStSet + 47, 0)
    memory.setint8(pStSet + 56, 1)
    nameTag = true
end

function nameTagOff()
    if not nameTag then return end
    local pStSet = sampGetServerSettingsPtr()
    memory.setfloat(pStSet + 39, NTdist)
    memory.setint8(pStSet + 47, NTwalls)
    memory.setint8(pStSet + 56, NTshow)
    nameTag = false
end

function explode_argb(argb)
    local a = bit.band(bit.rshift(argb, 24), 0xFF)
    local r = bit.band(bit.rshift(argb, 16), 0xFF)
    local g = bit.band(bit.rshift(argb, 8), 0xFF)
    local b = bit.band(argb, 0xFF)
    return a, r, g, b
end

local function join_argb(a, r, g, b)
    local argb = b
    argb = bit.bor(argb, bit.lshift(g, 8))
    argb = bit.bor(argb, bit.lshift(r, 16))
    argb = bit.bor(argb, bit.lshift(a, 24))
    return argb
end

local function saveConfig()
    main_cfg.settings.agm_togphone = st.cfg_agm_togphone[0]
    main_cfg.settings.warn_rvanka = st.cfg_warn_rvanka[0]
    main_cfg.settings.warn_cheat_weap = st.cfg_warn_cheat_weap[0]
    main_cfg.settings.auto_alogin = st.cfg_auto_alogin[0]
    main_cfg.settings.auto_open_report = st.cfg_auto_open_report[0]
    main_cfg.settings.alogin_pass = tostring(ffi.string(st.cfg_alogin_pass))
    main_cfg.settings.theme = st.current_theme[0]
    main_cfg.hotkeys.menu = st.hk_menu[0]
    main_cfg.hotkeys.report = st.hk_report[0]
    main_cfg.hotkeys.rules = st.hk_rules[0]
    main_cfg.hotkeys.ghetto = st.hk_ghetto[0]
    main_cfg.hotkeys.invis = st.hk_invis[0]
    main_cfg.admin.clickwarp = st.cfg_adm_clickwarp[0]
    main_cfg.admin.fast_enter = st.cfg_adm_fast_enter[0]
    main_cfg.admin.gm_car = st.cfg_adm_gm_car[0]
    main_cfg.admin.speedhack = st.cfg_adm_speedhack[0]
    main_cfg.admin.invis = st.cfg_adm_invis[0]

    main_cfg.admin.sh_limit = st.sh_limit[0]
    main_cfg.admin.sh_mult = st.sh_mult[0]
    main_cfg.admin.sh_timestep = st.sh_timestep[0]
    main_cfg.admin.sh_safe_train = st.sh_safe_train[0]
    main_cfg.admin.sh_key = ffi.string(st.sh_key)
    
    main_cfg.admin.bt_active = st.cfg_bt_active[0]
    main_cfg.admin.bt_show_id = st.cfg_bt_show_id[0]
    main_cfg.admin.bt_color_ped = {st.cfg_bt_color_ped[0], st.cfg_bt_color_ped[1], st.cfg_bt_color_ped[2]}
    main_cfg.admin.bt_color_car = {st.cfg_bt_color_car[0], st.cfg_bt_color_car[1], st.cfg_bt_color_car[2]}
    main_cfg.admin.bt_color_obj = {st.cfg_bt_color_obj[0], st.cfg_bt_color_obj[1], st.cfg_bt_color_obj[2]}
    main_cfg.admin.bt_thickness = st.cfg_bt_thickness[0]
    main_cfg.admin.bt_time = st.cfg_bt_time[0]
    
    main_cfg.admin.airbreak = st.cfg_ab_state[0]
    main_cfg.admin.ab_speed_player = st.cfg_ab_speed_player[0]
    main_cfg.admin.ab_speed_vehicle = st.cfg_ab_speed_vehicle[0]
    main_cfg.admin.ab_speed_passenger = st.cfg_ab_speed_passenger[0]
    main_cfg.admin.ab_sync_player = st.cfg_ab_sync_player[0]
    main_cfg.admin.ab_sync_vehicle = st.cfg_ab_sync_vehicle[0]
    main_cfg.admin.ab_sync_passenger = st.cfg_ab_sync_passenger[0]
    
    main_cfg.admin.wh_state = st.cfg_wh_state[0]
    main_cfg.admin.wh_mode = st.cfg_wh_mode[0]
    main_cfg.admin.wh_name_height = st.cfg_wh_name_height[0]
    main_cfg.admin.wh_bone_thick = st.cfg_wh_bone_thick[0]
    main_cfg.admin.wh_distance = st.cfg_wh_distance[0]
    main_cfg.admin.nobike_active = st.nb_active[0]

    main_cfg.templates = { count = #report_tpls }
    for i, t in ipairs(report_tpls) do
        main_cfg.templates["name_"..i] = u8:decode(t.name)
        main_cfg.templates["text_"..i] = u8:decode(t.text)
    end
    inicfg.save(main_cfg, config_file)
end

function onScriptTerminate(script, quitGame)
    if script == thisScript() then 
        saveConfig()
        nameTagOff()
    end
end

local function ApplyTheme(theme_idx)
    local style = imgui.GetStyle()
    local colors = style.Colors
    
    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.06, 0.06, 0.06, 0.85)
    colors[imgui.Col.ChildBg]  = imgui.ImVec4(0.08, 0.08, 0.08, 0.00)
    colors[imgui.Col.PopupBg]  = imgui.ImVec4(0.08, 0.08, 0.08, 1.00)
    colors[imgui.Col.Border]   = imgui.ImVec4(0.15, 0.15, 0.15, 1.00)
    colors[imgui.Col.BorderShadow] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[imgui.Col.FrameBg]  = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.15, 0.15, 0.15, 1.00)
    colors[imgui.Col.FrameBgActive]  = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)

    local r, g, b = 0.90, 0.25, 0.35
    if theme_idx == 1 then r, g, b = 0.95, 0.75, 0.15 elseif theme_idx == 2 then r, g, b = 0.25, 0.85, 0.35 elseif theme_idx == 3 then r, g, b = 0.20, 0.85, 0.90 elseif theme_idx == 4 then r, g, b = 0.30, 0.45, 0.95 elseif theme_idx == 5 then r, g, b = 0.60, 0.25, 0.95 end

    colors[imgui.Col.Text]             = imgui.ImVec4(0.95, 0.95, 0.95, 1.00)
    colors[imgui.Col.TextDisabled]     = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[imgui.Col.ScrollbarBg]      = imgui.ImVec4(0.0, 0.0, 0.0, 0.0)
    colors[imgui.Col.ScrollbarGrab]    = imgui.ImVec4(r, g, b, 0.6)
    colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(r, g, b, 0.8)
    colors[imgui.Col.ScrollbarGrabActive]  = imgui.ImVec4(r, g, b, 1.0)
    style.ScrollbarRounding = 12.0
    style.ScrollbarSize = 6.0
    colors[imgui.Col.Button]           = imgui.ImVec4(r, g, b, 0.70)
    colors[imgui.Col.ButtonHovered]    = imgui.ImVec4(r, g, b, 0.90)
    colors[imgui.Col.ButtonActive]     = imgui.ImVec4(r, g, b, 1.00)
    colors[imgui.Col.Header]           = imgui.ImVec4(r, g, b, 0.60)
    colors[imgui.Col.HeaderHovered]    = imgui.ImVec4(r, g, b, 0.80)
    colors[imgui.Col.HeaderActive]     = imgui.ImVec4(r, g, b, 1.00)
    colors[imgui.Col.Separator]        = imgui.ImVec4(0.15, 0.15, 0.15, 1.00)
    colors[imgui.Col.SeparatorHovered] = imgui.ImVec4(r, g, b, 0.50)
    colors[imgui.Col.SeparatorActive]  = imgui.ImVec4(r, g, b, 0.80)
    colors[imgui.Col.CheckMark]        = imgui.ImVec4(r, g, b, 1.00)
    colors[imgui.Col.SliderGrab]       = imgui.ImVec4(r, g, b, 0.80)
    colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(r, g, b, 1.00)
    colors[imgui.Col.TitleBg]          = imgui.ImVec4(0.06, 0.06, 0.06, 1.00)
    colors[imgui.Col.TitleBgActive]    = imgui.ImVec4(0.06, 0.06, 0.06, 1.00)
    colors[imgui.Col.TitleBgCollapsed] = imgui.ImVec4(0.06, 0.06, 0.06, 1.00)
end

if not _G.toggle_anim_state then _G.toggle_anim_state = {} end

local function HoverTooltip(desc)
    if imgui.IsItemHovered() then
        imgui.PushStyleColor(imgui.Col.PopupBg, imgui.ImVec4(0.08, 0.08, 0.08, 0.95))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.3, 0.3, 0.3, 0.5))
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 8.0)
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(350.0)
        imgui.TextUnformatted(desc)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
        imgui.PopStyleVar()
        imgui.PopStyleColor(2)
    end
end

local function CustomToggle(label, bool_val, tooltip_desc)
    local p = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()
    local radius = 9.0; local width = 35.0; local height = radius * 2.0; local pos = imgui.GetCursorPos()

    imgui.InvisibleButton(label, imgui.ImVec2(width, height))
    local clicked = false
    if imgui.IsItemClicked() then 
        bool_val[0] = not bool_val[0]
        pcall(function() addOneOffSound(0,0,0,1083) end)
        saveConfig() 
        clicked = true
    end

    if tooltip_desc then HoverTooltip(tooltip_desc) end

    if _G.toggle_anim_state[label] == nil then
        _G.toggle_anim_state[label] = bool_val[0] and 1.0 or 0.0
    end
    
    local target = bool_val[0] and 1.0 or 0.0
    local current = _G.toggle_anim_state[label]
    if current ~= target then
        current = current + (target - current) * (imgui.GetIO().DeltaTime * 15.0)
        if math.abs(current - target) < 0.01 then current = target end
        _G.toggle_anim_state[label] = current
    end
    local t = current
    
    local col_bg_off = imgui.ImVec4(0.3, 0.3, 0.3, 1.0)
    local col_bg_on = imgui.GetStyle().Colors[imgui.Col.Button]
    local bg_r = col_bg_off.x + (col_bg_on.x - col_bg_off.x) * t
    local bg_g = col_bg_off.y + (col_bg_on.y - col_bg_off.y) * t
    local bg_b = col_bg_off.z + (col_bg_on.z - col_bg_off.z) * t
    
    local col_bg = imgui.GetColorU32Vec4(imgui.ImVec4(bg_r, bg_g, bg_b, 1.0))
    local col_circle = imgui.GetColorU32Vec4(imgui.ImVec4(1.0, 1.0, 1.0, 1.0))

    draw_list:AddRectFilled(p, imgui.ImVec2(p.x + width, p.y + height), col_bg, height * 0.5)
    draw_list:AddCircleFilled(imgui.ImVec2(p.x + radius + t * (width - radius * 2.0), p.y + radius), radius - 1.5, col_circle)
    
    imgui.SameLine(nil, 10); imgui.SetCursorPosY(pos.y + 2); imgui.Text(label)
    if tooltip_desc then HoverTooltip(tooltip_desc) end
    
    return clicked
end

local function DrawHotkeyBtn(id_name, label, bind_ptr)
    local vk = bind_ptr[0]
    local btn_text = (vk == 0) and "Не назначено" or (vkeys.id_to_name(vk) or "Кл."..vk)

    if st.current_binding == id_name then
        btn_text = "Нажмите..."
        for k = 3, 255 do
            if imgui.IsKeyPressed(k, false) then
                if k == vkeys.VK_ESCAPE or k == vkeys.VK_BACK then bind_ptr[0] = 0 else bind_ptr[0] = k end
                st.current_binding = nil; saveConfig(); break
            end
        end
    end

    if imgui.Button(btn_text .. "##" .. id_name, imgui.ImVec2(110, 22)) then st.current_binding = id_name end
    if imgui.IsItemHovered() and st.current_binding ~= id_name then imgui.SetTooltip("ЛКМ - назначить\nESC/Backspace - очистить") end
    imgui.SameLine(); imgui.SetCursorPosY(imgui.GetCursorPosY() + 2); imgui.Text(label)
end

imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    style.WindowRounding = 10.0; style.FrameRounding = 6.0; style.ChildRounding = 8.0; style.PopupRounding = 6.0
    style.ScrollbarRounding = 6.0; style.GrabRounding = 4.0
    style.WindowPadding = imgui.ImVec2(12, 12); style.FramePadding = imgui.ImVec2(6, 4); style.ItemSpacing = imgui.ImVec2(8, 6)
    ApplyTheme(st.current_theme[0])
    local fonts = imgui.GetIO().Fonts
    local fontPaths = {'C:/Windows/Fonts/arial.ttf', 'C:/Windows/Fonts/tahoma.ttf', 'C:/Windows/Fonts/verdana.ttf'}
    local fontLoaded = false
    for _, path in ipairs(fontPaths) do
        local f = io.open(path, 'rb')
        if f then f:close(); fonts:AddFontFromFileTTF(path, 16.0, nil, cyrRanges); fontLoaded = true; break end
    end
    if not fontLoaded then fonts:AddFontDefault() end
end)

local function loadNextReport()
    if #st.report_queue > 0 then st.active_report = table.remove(st.report_queue, 1) else st.active_report = nil end
end

-- === ФУНКЦИЯ ДЛЯ ПРАВИЛЬНОГО СКЛОНЕНИЯ СЛОВ (час/часа/часов) ===
local function getDeclension(num, form1, form2, form5)
    local n100 = num % 100
    local n10 = num % 10
    if n100 >= 11 and n100 <= 19 then return form5 end
    if n10 == 1 then return form1 end
    if n10 >= 2 and n10 <= 4 then return form2 end
    return form5
end

-- === FFI ДЛЯ БУФЕРА ОБМЕНА (СОХРАНЕНИЕ СМАЙЛОВ) ===
pcall(function()
    ffi.cdef[[
        int OpenClipboard(void*);
        int CloseClipboard();
        int EmptyClipboard();
        void* GetClipboardData(unsigned int);
        void* SetClipboardData(unsigned int, void*);
        void* GlobalAlloc(unsigned int, size_t);
        void* GlobalLock(void*);
        int GlobalUnlock(void*);
        int MultiByteToWideChar(unsigned int, unsigned int, const char*, int, wchar_t*, int);
        int WideCharToMultiByte(unsigned int, unsigned int, const wchar_t*, int, char*, int, const char*, int*);
    ]]
end)
local user32 = ffi.load('user32')
local kernel32 = ffi.load('kernel32')

local function GetClipboardUTF8()
    if user32.OpenClipboard(nil) == 0 then return "" end
    local hData = user32.GetClipboardData(13) -- 13 = CF_UNICODETEXT
    if hData == nil then user32.CloseClipboard(); return "" end
    local pData = kernel32.GlobalLock(hData)
    if pData == nil then user32.CloseClipboard(); return "" end
    local len = kernel32.WideCharToMultiByte(65001, 0, ffi.cast("const wchar_t*", pData), -1, nil, 0, nil, nil)
    local buf = ffi.new("char[?]", len)
    kernel32.WideCharToMultiByte(65001, 0, ffi.cast("const wchar_t*", pData), -1, buf, len, nil, nil)
    kernel32.GlobalUnlock(hData)
    user32.CloseClipboard()
    return ffi.string(buf, len - 1)
end

local function SetClipboardUTF8(text)
    if user32.OpenClipboard(nil) == 0 then return end
    user32.EmptyClipboard()
    local len = kernel32.MultiByteToWideChar(65001, 0, text, -1, nil, 0)
    local hMem = kernel32.GlobalAlloc(0x0002, len * 2) -- 0x0002 = GMEM_MOVEABLE
    local pMem = kernel32.GlobalLock(hMem)
    kernel32.MultiByteToWideChar(65001, 0, text, -1, ffi.cast("wchar_t*", pMem), len)
    kernel32.GlobalUnlock(hMem)
    user32.SetClipboardData(13, hMem)
    user32.CloseClipboard()
end

-- === ОСНОВНОЙ ПОТОК ПРОВЕРКИ НОРМЫ ===
local function startNormCheck(use_clipboard)
    lua_thread.create(function()
        st.norm_is_checking = true
        local lines = {}
        local input_str = ""
        
        -- Выбираем, откуда брать текст
        if use_clipboard then
            input_str = GetClipboardUTF8()
        else
            input_str = ffi.string(st.norm_input_buf)
        end
        
        -- Разбиваем текст на строки
        for s in (input_str .. "\n"):gmatch("(.-)\n") do
            s = s:gsub("\r", "")
            if s ~= "" or input_str:find("\n") then
                table.insert(lines, s)
            end
        end

        local out_lines = {}
        st.norm_total[0] = 0
        
        -- Считаем админов
        for _, line in ipairs(lines) do
            local nick = line:match("([A-Za-z0-9]+_[A-Za-z0-9]+)")
            if nick and not line:find("Основатель Сервера") then
                st.norm_total[0] = st.norm_total[0] + 1
            end
        end

        st.norm_progress[0] = 0

        for _, line in ipairs(lines) do
            local nick = line:match("([A-Za-z0-9]+_[A-Za-z0-9]+)")
            if nick then
                if line:find("Основатель Сервера") then
                    table.insert(out_lines, line .. " - маладец")
                else
                    st.norm_current_result = nil
                    sampSendChat("/astats " .. nick)

                    local timeout = os.clock() + 5.0
                    while st.norm_current_result == nil and os.clock() < timeout do
                        wait(50)
                    end

                    if st.norm_current_result then
                        table.insert(out_lines, line .. " - " .. st.norm_current_result)
                    else
                        table.insert(out_lines, line .. " - аккаунт не найден")
                    end
                    
                    st.norm_progress[0] = st.norm_progress[0] + 1
                    wait(1200)
                end
            else
                table.insert(out_lines, line)
            end
            
            -- Выводим предпросмотр в окно (смайлы там будут сломаны, но это только для визуала)
            local preview_text = table.concat(out_lines, "\n")
            if #preview_text < 8100 then
                ffi.copy(st.norm_output_buf, preview_text)
            end
        end
        
        -- Если юзали буфер, сохраняем ИДЕАЛЬНЫЙ результат обратно в буфер!
        local final_text = table.concat(out_lines, "\n")
        if use_clipboard then
            SetClipboardUTF8(final_text)
            sampAddChatMessage(u8:decode("[GibsonHelper] Проверка завершена! Готовый список (со смайлами) скопирован в буфер обмена."), 0x00FF00)
        end

        st.norm_is_checking = false
    end)
end

local newFrame = imgui.OnFrame(
    function() return st.renderWindow[0] or st.reportWindow[0] end,
    function(player)
        if st.reportWindow[0] then
            imgui.SetNextWindowSize(imgui.ImVec2(460, 480), imgui.Cond.FirstUseEver)
            
            -- Секрет фикса дергания: ###ReportWindow фиксирует ID окна, даже если заголовок меняется
            local title = "Жалоба/Вопрос"
            if #st.report_queue > 0 then 
                title = title .. " (В очереди: " .. #st.report_queue .. ")###ReportWindow" 
            else
                title = title .. "###ReportWindow"
            end

            if imgui.Begin(title, st.reportWindow, imgui.WindowFlags.NoCollapse) then
                local has_report = st.active_report ~= nil
                
                -- Блок репорта с фиксированной высотой (Child), убирает дергание от длинного текста
                if has_report then
                    imgui.Text("От: " .. st.active_report.name .. " [" .. st.active_report.id .. "]")
                    imgui.Separator()
                    imgui.BeginChild("ReportText", imgui.ImVec2(0, 55), true) -- Рамка вокруг текста
                    imgui.TextWrapped(st.active_report.text)
                    imgui.EndChild()
                else
                    imgui.Text("От: Нет активных репортов")
                    imgui.Separator()
                    imgui.BeginChild("ReportText", imgui.ImVec2(0, 55), true)
                    imgui.TextDisabled("Очередь пуста. Ожидайте новые вопросы...")
                    imgui.EndChild()
                end
                
                imgui.Separator(); imgui.Spacing(); imgui.Text("Свой ответ:")
                
                -- Выравниваем текст ввода в одну линию с идеальными отступами
                imgui.AlignTextToFramePadding() 
                imgui.TextDisabled("Уважаемый игрок,")
                imgui.SameLine(nil, 5)
                imgui.PushItemWidth(210)
                imgui.InputText("##custom_ans", st.custom_reply_buf, ffi.sizeof(st.custom_reply_buf))
                imgui.PopItemWidth()
                imgui.SameLine()
                
                if imgui.Button("Ответить", imgui.ImVec2(80, 24)) and has_report then
                    local tid = st.active_report.id
                    local ans = ffi.string(st.custom_reply_buf)
                    if ans ~= "" then
                        sampSendChat(u8:decode("/pm " .. tid .. " Уважаемый игрок, " .. ans))
                        st.custom_reply_buf[0] = 0
                        loadNextReport()
                    end
                end

                imgui.Separator(); imgui.Spacing(); imgui.Text("Системные команды:")

                if not has_report then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.3, 0.3, 0.3, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.3, 0.3, 0.3, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.3, 0.3, 0.3, 1.0))
                end

               -- Идеальная сетка кнопок
                local sys_btn_w, sys_btn_h = 104, 30
                if imgui.Button("veh", imgui.ImVec2(sys_btn_w, sys_btn_h)) and has_report then
                    local tid = st.active_report.id; lua_thread.create(function() sampSendChat(u8:decode("/pm " .. tid .. " Уважаемый игрок, выполнено")); wait(1000); sampSendChat("/veh " .. tid) end); loadNextReport()
                end
                imgui.SameLine()
                if imgui.Button("slap", imgui.ImVec2(sys_btn_w, sys_btn_h)) and has_report then
                    local tid = st.active_report.id; lua_thread.create(function() sampSendChat(u8:decode("/pm " .. tid .. " Уважаемый игрок, исполнено")); wait(1000); sampSendChat("/slap " .. tid) end); loadNextReport()
                end
                imgui.SameLine()
                if imgui.Button("carhp", imgui.ImVec2(sys_btn_w, sys_btn_h)) and has_report then
                    local tid = st.active_report.id; lua_thread.create(function() sampSendChat(u8:decode("/pm " .. tid .. " Уважаемый игрок, исполнено")); wait(1000); sampSendChat("/carhp " .. tid) end); loadNextReport()
                end
                imgui.SameLine()
                if imgui.Button("spawn", imgui.ImVec2(sys_btn_w, sys_btn_h)) and has_report then
                    local tid = st.active_report.id; lua_thread.create(function() sampSendChat(u8:decode("/pm " .. tid .. " Уважаемый игрок, исполнено")); wait(1000); sampSendChat("/spawn " .. tid) end); loadNextReport()
                end

                if imgui.Button("Передам", imgui.ImVec2(sys_btn_w, sys_btn_h)) and has_report then
                    local tid = st.active_report.id; local tname = st.active_report.name; local ttext = st.active_report.text
                    lua_thread.create(function() sampSendChat(u8:decode("/pm " .. tid .. " Уважаемый игрок, передам")); wait(1000); sampSendChat(u8:decode("/a Репорт от " .. tname .. "[" .. tid .. "]: " .. ttext)) end); loadNextReport()
                end
                imgui.SameLine()
                if imgui.Button("Слежу", imgui.ImVec2(sys_btn_w, sys_btn_h)) and has_report then
                    local tid = st.active_report.id; lua_thread.create(function() sampSendChat(u8:decode("/pm " .. tid .. " Уважаемый игрок, слежу")); wait(1000); sampSendChat("/re " .. tid) end); loadNextReport()
                end
                imgui.SameLine()
                if imgui.Button("Иду", imgui.ImVec2(sys_btn_w, sys_btn_h)) and has_report then
                    local tid = st.active_report.id; lua_thread.create(function() sampSendChat(u8:decode("/pm " .. tid .. " Уважаемый игрок, спешу вам помочь")); wait(1000); sampSendChat("/goto " .. tid) end); loadNextReport()
                end

                imgui.Separator(); imgui.Spacing(); imgui.Text("Быстрые ответы:")

                for i, tpl in ipairs(report_tpls) do
                    if imgui.Button(tpl.name, imgui.ImVec2(138, 30)) then
                        if has_report then sampSendChat("/pm " .. st.active_report.id .. " " .. u8:decode(tpl.text)); loadNextReport() end
                    end
                    if i % 3 ~= 0 and i ~= #report_tpls then imgui.SameLine() end
                end

                if not has_report then imgui.PopStyleColor(3) end

                imgui.Separator(); imgui.Spacing()
                if has_report then
                    if imgui.Button("Пропустить", imgui.ImVec2(138, 30)) then loadNextReport() end
                else
                    if imgui.Button("Закрыть", imgui.ImVec2(138, 30)) then st.reportWindow[0] = false end
                end
            end
            imgui.End()
        end

                                                if st.renderWindow[0] then
            imgui.SetNextWindowSize(imgui.ImVec2(850, 540), imgui.Cond.FirstUseEver)
            imgui.SetNextWindowPos(imgui.ImVec2(imgui.GetIO().DisplaySize.x / 2, imgui.GetIO().DisplaySize.y / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))

            local flags = bit.bor(imgui.WindowFlags.NoCollapse, imgui.WindowFlags.NoTitleBar)
            if imgui.Begin("Основное меню", st.renderWindow, flags) then
                local p = imgui.GetCursorScreenPos()
                local draw_list = imgui.GetWindowDrawList()
                local win_w = imgui.GetWindowWidth()
                local win_h = imgui.GetWindowHeight()
                local win_pos = imgui.GetWindowPos()
                local style = imgui.GetStyle()
                local accent = style.Colors[imgui.Col.ButtonActive]

                -- Chroma Mode Logic
                if not _G.cfg_chroma then _G.cfg_chroma = { [0] = false } end
                if _G.cfg_chroma[0] then
                    local t = os.clock()
                    local r = math.sin(t * 1.5) * 0.5 + 0.5
                    local g = math.sin(t * 1.5 + 2.09) * 0.5 + 0.5
                    local b = math.sin(t * 1.5 + 4.18) * 0.5 + 0.5
                    local style = imgui.GetStyle()
                    style.Colors[imgui.Col.Button] = imgui.ImVec4(r, g, b, 0.70)
                    style.Colors[imgui.Col.ButtonHovered] = imgui.ImVec4(r, g, b, 0.90)
                    style.Colors[imgui.Col.ButtonActive] = imgui.ImVec4(r, g, b, 1.00)
                    style.Colors[imgui.Col.Header] = imgui.ImVec4(r, g, b, 0.60)
                    style.Colors[imgui.Col.HeaderHovered] = imgui.ImVec4(r, g, b, 0.80)
                    style.Colors[imgui.Col.HeaderActive] = imgui.ImVec4(r, g, b, 1.00)
                    style.Colors[imgui.Col.CheckMark] = imgui.ImVec4(r, g, b, 1.00)
                    style.Colors[imgui.Col.SliderGrab] = imgui.ImVec4(r, g, b, 0.80)
                    style.Colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(r, g, b, 1.00)
                    style.Colors[imgui.Col.ScrollbarGrab] = imgui.ImVec4(r, g, b, 0.60)
                    style.Colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(r, g, b, 0.80)
                    style.Colors[imgui.Col.ScrollbarGrabActive] = imgui.ImVec4(r, g, b, 1.00)
                    _G.last_chroma = true
                elseif _G.last_chroma then
                    _G.last_chroma = false
                    ApplyTheme(st.current_theme[0])
                end
                
                accent = style.Colors[imgui.Col.ButtonActive]

                -- Constellation Background Animation with Mouse Magnetism
                local time = os.clock()
                local num_particles = 50
                local points = {}
                local mouse_pos = imgui.GetMousePos()
                
                -- Generate positions
                for i = 1, num_particles do
                    local speed_x = math.sin(i * 123.456) * 15
                    local speed_y = math.cos(i * 987.654) * 15
                    local x = win_pos.x + ((i * 73 + time * speed_x) % win_w)
                    local y = win_pos.y + ((i * 59 + time * speed_y) % win_h)
                    
                    -- Magnetize to mouse
                    local dx_m = mouse_pos.x - x
                    local dy_m = mouse_pos.y - y
                    local dist_m = math.sqrt(dx_m*dx_m + dy_m*dy_m)
                    if dist_m < 150.0 then
                        local force = (150.0 - dist_m) / 150.0
                        x = x + dx_m * force * 0.4
                        y = y + dy_m * force * 0.4
                        draw_list:AddLine(imgui.ImVec2(x, y), mouse_pos, imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, force * 0.5)), 1.0)
                    end
                    
                    table.insert(points, {x=x, y=y})
                    
                    local radius = (i % 3) * 0.5 + 1.0
                    draw_list:AddCircleFilled(imgui.ImVec2(x, y), radius, imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, 0.4)))
                end
                
                -- Mouse trails
                if not _G.mouse_history then _G.mouse_history = {} end
                table.insert(_G.mouse_history, {x = mouse_pos.x, y = mouse_pos.y, time = os.clock()})
                
                while #_G.mouse_history > 0 and (os.clock() - _G.mouse_history[1].time > 0.3) do
                    table.remove(_G.mouse_history, 1)
                end
                
                for i = 1, #_G.mouse_history - 1 do
                    local p1 = _G.mouse_history[i]
                    local p2 = _G.mouse_history[i+1]
                    local age = (os.clock() - p1.time) / 0.3
                    local alpha = (1.0 - age) * 0.6
                    draw_list:AddLine(imgui.ImVec2(p1.x, p1.y), imgui.ImVec2(p2.x, p2.y), imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, alpha)), 4.0 * (1.0 - age))
                end

                -- Connect nearby particles
                local max_dist = 90.0
                for i = 1, #points do
                    for j = i + 1, #points do
                        local dx = points[i].x - points[j].x
                        local dy = points[i].y - points[j].y
                        local dist = math.sqrt(dx*dx + dy*dy)
                        
                        if dist < max_dist then
                            local alpha = 0.4 * (1.0 - (dist / max_dist))
                            draw_list:AddLine(imgui.ImVec2(points[i].x, points[i].y), imgui.ImVec2(points[j].x, points[j].y), imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, alpha)), 1.0)
                        end
                    end
                end

                -- Header: Highly Detailed Animated Atom Logo
                local cx = win_pos.x + 45
                local cy = win_pos.y + 40
                
                -- Nucleus glow
                local pulse = (math.sin(time * 3.0) * 0.5 + 0.5)
                draw_list:AddCircleFilled(imgui.ImVec2(cx, cy), 12.0 + pulse * 6.0, imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, 0.15)))
                
                -- Dynamic nucleus (3 inner spinning circles + core)
                for i = 1, 3 do
                    local core_angle = time * 4.0 + (i * math.pi * 2 / 3)
                    local cx_offset = math.cos(core_angle) * 3.0
                    local cy_offset = math.sin(core_angle) * 3.0
                    draw_list:AddCircleFilled(imgui.ImVec2(cx + cx_offset, cy + cy_offset), 4.5, imgui.GetColorU32Vec4(accent))
                end
                draw_list:AddCircleFilled(imgui.ImVec2(cx, cy), 4.0, imgui.GetColorU32Vec4(imgui.ImVec4(1,1,1,0.8)))

                -- Orbital rings and electrons
                local num_electrons = 3
                for i = 1, num_electrons do
                    local orbit_rx = 26.0
                    local orbit_ry = 9.0
                    local orbit_rot = (i * math.pi / num_electrons) + time * 0.3 -- slowly rotate the rings themselves
                    
                    -- Draw the orbital ring (approximate rotated ellipse)
                    local orbit_points = 24
                    for j = 0, orbit_points - 1 do
                        local a1 = (j / orbit_points) * math.pi * 2
                        local a2 = ((j + 1) / orbit_points) * math.pi * 2
                        
                        local ex1 = math.cos(a1) * orbit_rx
                        local ey1 = math.sin(a1) * orbit_ry
                        local ex2 = math.cos(a2) * orbit_rx
                        local ey2 = math.sin(a2) * orbit_ry
                        
                        local rx1 = cx + (ex1 * math.cos(orbit_rot) - ey1 * math.sin(orbit_rot))
                        local ry1 = cy + (ex1 * math.sin(orbit_rot) + ey1 * math.cos(orbit_rot))
                        local rx2 = cx + (ex2 * math.cos(orbit_rot) - ey2 * math.sin(orbit_rot))
                        local ry2 = cy + (ex2 * math.sin(orbit_rot) + ey2 * math.cos(orbit_rot))
                        
                        draw_list:AddLine(imgui.ImVec2(rx1, ry1), imgui.ImVec2(rx2, ry2), imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, 0.3)), 1.5)
                    end
                    
                    -- Draw the electron
                    local angle = time * 3.5 + (i * math.pi * 2 / 3)
                    local ex = math.cos(angle) * orbit_rx
                    local ey = math.sin(angle) * orbit_ry
                    local rx = cx + (ex * math.cos(orbit_rot) - ey * math.sin(orbit_rot))
                    local ry = cy + (ex * math.sin(orbit_rot) + ey * math.cos(orbit_rot))
                    
                    draw_list:AddCircleFilled(imgui.ImVec2(rx, ry), 7.0, imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, 0.5))) -- glow
                    draw_list:AddCircleFilled(imgui.ImVec2(rx, ry), 3.5, imgui.GetColorU32Vec4(imgui.ImVec4(1,1,1,0.9))) -- solid core
                end

                -- Header Text with glow
                local text_x, text_y = win_pos.x + 95, win_pos.y + 20
                for i = 1, 2 do
                    draw_list:AddText(imgui.ImVec2(text_x, text_y), imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, 0.3)), "Gibson Helper")
                end
                draw_list:AddText(imgui.ImVec2(text_x, text_y), imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, 1.0)), "Gibson Helper")
                
                imgui.SetCursorPos(imgui.ImVec2(95, 37))
                imgui.TextDisabled("Version 1.1")

                -- Close Button
                imgui.SetCursorPos(imgui.ImVec2(win_w - 40, 15))
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.8, 0.2, 0.2, 0.5))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1.0, 0.2, 0.2, 0.8))
                if imgui.Button("X", imgui.ImVec2(25, 25)) then st.renderWindow[0] = false end
                imgui.PopStyleColor(3)

                draw_list:AddLine(imgui.ImVec2(win_pos.x, win_pos.y + 80), imgui.ImVec2(win_pos.x + win_w, win_pos.y + 80), imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, 0.3)), 1.0)
                
                imgui.SetCursorPos(imgui.ImVec2(15, 95))
                
                                -- Global Animation State for Smooth Transitions
                if not _G.gh_anim_progress then
                    _G.gh_anim_progress = 1.0
                end
                
                -- Update animation progress
                if _G.gh_anim_progress < 1.0 then
                    _G.gh_anim_progress = _G.gh_anim_progress + (imgui.GetIO().DeltaTime * 6.0)
                    if _G.gh_anim_progress > 1.0 then _G.gh_anim_progress = 1.0 end
                end

                                local function DrawTab(label, tab_id)
                    local is_active = (st.activeTab[0] == tab_id)
                    local colors_style = imgui.GetStyle().Colors
                    
                    if is_active then
                        local breath = (math.sin(os.clock() * 4.0) * 0.15) + 0.85
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(colors_style[imgui.Col.ButtonActive].x, colors_style[imgui.Col.ButtonActive].y, colors_style[imgui.Col.ButtonActive].z, breath))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, colors_style[imgui.Col.ButtonActive])
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
                    else
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.12, 0.12, 0.12, 0.6))
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.7, 0.7, 0.7, 1.0))
                    end
                    
                    local style_local = imgui.GetStyle()
                    local old_rounding = style_local.FrameRounding
                    style_local.FrameRounding = 12.0
                    
                    if imgui.Button(label, imgui.ImVec2(190, 32)) then 
                        if st.activeTab[0] ~= tab_id then
                            pcall(function() addOneOffSound(0, 0, 0, 1083) end)
                            st.activeTab[0] = tab_id
                            _G.gh_anim_progress = 0.0
                        end
                    end
                    
                    style_local.FrameRounding = old_rounding
                    imgui.PopStyleColor(3)
                end

                local function DrawIconButton(id, icon_type, size)
                    local p = imgui.GetCursorScreenPos()
                    local draw_list = imgui.GetWindowDrawList()
                    local cx = p.x + size.x / 2
                    local cy = p.y + size.y / 2

                    local clicked = imgui.InvisibleButton(id, size)
                    local is_hovered = imgui.IsItemHovered()
                    local is_active = imgui.IsItemActive()

                    local bg_color = is_active and imgui.GetColorU32Vec4(imgui.ImVec4(0.2, 0.2, 0.2, 0.8))
                                  or (is_hovered and imgui.GetColorU32Vec4(imgui.ImVec4(0.15, 0.15, 0.15, 0.6))
                                  or imgui.GetColorU32Vec4(imgui.ImVec4(0.1, 0.1, 0.1, 0.0)))
                    draw_list:AddRectFilled(p, imgui.ImVec2(p.x + size.x, p.y + size.y), bg_color, 8.0)

                    local color = is_active and imgui.GetColorU32Vec4(accent)
                                  or (is_hovered and imgui.GetColorU32Vec4(imgui.ImVec4(accent.x, accent.y, accent.z, 0.8))
                                  or imgui.GetColorU32Vec4(imgui.ImVec4(0.5, 0.5, 0.5, 0.6)))

                    if icon_type == "power" then
                        draw_list:PathArcTo(imgui.ImVec2(cx, cy), 7.0, -math.pi * 0.35, math.pi * 1.35, 20)
                        draw_list:PathStroke(color, false, 2.0)
                        draw_list:AddLine(imgui.ImVec2(cx, cy - 7.0), imgui.ImVec2(cx, cy + 1.0), color, 2.0)
                    elseif icon_type == "restart" then
                        draw_list:PathArcTo(imgui.ImVec2(cx, cy), 7.0, -math.pi * 0.15, math.pi * 1.5, 20)
                        draw_list:PathStroke(color, false, 2.0)
                        local px, py = cx + math.cos(math.pi * 1.5) * 7.0, cy + math.sin(math.pi * 1.5) * 7.0
                        draw_list:AddTriangleFilled(imgui.ImVec2(px - 3, py - 3), imgui.ImVec2(px + 4, py), imgui.ImVec2(px - 3, py + 3), color)
                    end
                    
                    return clicked
                end

                imgui.Columns(2, "MainLayout", false); imgui.SetColumnWidth(0, 220)

                imgui.BeginChild("LeftSidebar", imgui.ImVec2(210, 0), false)
                DrawTab("Настройки", 1); imgui.Spacing()
                DrawTab("Админ ПО", 2); imgui.Spacing()
                DrawTab("Авто-Репорт", 3); imgui.Spacing()
                DrawTab("Авто раздача", 4); imgui.Spacing()
                DrawTab("Мероприятия", 5); imgui.Spacing()
                DrawTab("Отборы", 6); imgui.Spacing()
                DrawTab("Разные функции", 7); imgui.Spacing()
                DrawTab("Правила сервера", 8); imgui.Spacing()
                DrawTab("Авто чек нормы", 9); imgui.Spacing()
                DrawTab("Авторы", 10)

                imgui.SetCursorPosY(imgui.GetWindowHeight() - 50)
                imgui.SetCursorPosX(imgui.GetCursorPosX() + 65)
                
                if DrawIconButton("btn_power", "power", imgui.ImVec2(35, 35)) then 
                    pcall(function() addOneOffSound(0,0,0,1083) end)
                    thisScript():unload() 
                end
                
                imgui.SameLine(0, 10)
                
                if DrawIconButton("btn_restart", "restart", imgui.ImVec2(35, 35)) then 
                    pcall(function() addOneOffSound(0,0,0,1083) end)
                    thisScript():reload() 
                end
                
                imgui.EndChild()
                imgui.NextColumn()

                -- Apply transition to RightContent
                local tab_alpha = _G.gh_anim_progress
                local tab_offset_y = (1.0 - _G.gh_anim_progress) * 20.0
                
                imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, tab_alpha)
                imgui.SetCursorPosY(imgui.GetCursorPosY() + tab_offset_y)
                imgui.BeginChild("RightContent", imgui.ImVec2(0, 0), false)

                if st.activeTab[0] == 1 then
                    imgui.PushItemWidth(200)
                    local profile_names = {"Профиль 1 (Основной)", "Профиль 2", "Профиль 3"}
                    local selected_profile = imgui.new.int(_G.current_profile_id - 1)
                    if imgui.Combo("##profile_selector", selected_profile, profile_names, #profile_names) then
                        local new_id = selected_profile[0] + 1
                        if new_id ~= _G.current_profile_id then
                            saveConfig()
                            master_cfg.profile.current = new_id
                            inicfg.save(master_cfg, master_cfg_name)
                            thisScript():reload()
                        end
                    end
                    imgui.PopItemWidth(); imgui.SameLine(nil, 15)
                    imgui.TextDisabled("Текущий профиль настроек")
                    imgui.Spacing(); imgui.Spacing()
                    
                    -- DASHBOARD
                    local function DrawWidget(title, value, x_offset, w)
                        local p = imgui.GetCursorScreenPos()
                        local dl = imgui.GetWindowDrawList()
                        local rect_min = imgui.ImVec2(p.x + x_offset, p.y + 5)
                        local rect_max = imgui.ImVec2(p.x + x_offset + w, p.y + 75)
                        local accent_color = imgui.GetStyle().Colors[imgui.Col.ButtonActive]
                        
                        dl:AddRectFilled(rect_min, rect_max, imgui.GetColorU32Vec4(imgui.ImVec4(0.12, 0.12, 0.12, 0.6)), 12.0)
                        dl:AddRect(rect_min, rect_max, imgui.GetColorU32Vec4(imgui.ImVec4(accent_color.x, accent_color.y, accent_color.z, 0.3)), 12.0, 15, 1.0)
                        
                        dl:AddText(imgui.ImVec2(rect_min.x + 15, rect_min.y + 12), imgui.GetColorU32Vec4(imgui.ImVec4(0.6, 0.6, 0.6, 1.0)), title)
                        dl:AddText(imgui.ImVec2(rect_min.x + 15, rect_min.y + 35), imgui.GetColorU32Vec4(accent_color), value)
                    end
                    
                    local dash_w = 580
                    local box_w = (dash_w - 45) / 4
                    
                    local fps = math.floor(1.0 / imgui.GetIO().DeltaTime)
                    local ping = 0
                    local result, p_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
                    if result then ping = sampGetPlayerPing(p_id) end
                    
                    local online = 0
                    for i = 0, sampGetMaxPlayerId() do if sampIsPlayerConnected(i) then online = online + 1 end end
                    
                    local hp = getCharHealth(PLAYER_PED)
                    
                    imgui.BeginChild("Dashboard", imgui.ImVec2(dash_w, 90), false)
                    DrawWidget("FPS", tostring(fps), 0, box_w)
                    DrawWidget("PING", tostring(ping).." ms", box_w + 15, box_w)
                    DrawWidget("ONLINE", tostring(online), (box_w + 15)*2, box_w)
                    DrawWidget("HEALTH", tostring(hp).." HP", (box_w + 15)*3, box_w)
                    imgui.EndChild()
                    imgui.Spacing()

                    imgui.BeginChild("SettingsToggles", imgui.ImVec2(280, 0), false)
                    imgui.Text("Основные настройки")
                    imgui.Separator(); imgui.Spacing()

                    CustomToggle("/agm /togphone при входе",   st.cfg_agm_togphone, "Автоматически выдает вам бессмертие и выключает мобильный телефон при каждом спавне."); imgui.Spacing()
                    CustomToggle("Предупреждения на рванку",   st.cfg_warn_rvanka, "Если игрок рядом использует чит 'Рванка', хелпер моментально предупредит вас сообщением в чат."); imgui.Spacing()
                    CustomToggle("Варнинги на запр. оружие",   st.cfg_warn_cheat_weap, "Предупреждает о выдаче запрещенного оружия (minigun, rpg) игроками в зоне стрима."); imgui.Spacing()
                    CustomToggle("Автоматический /alogin",     st.cfg_auto_alogin, "Сохраняет ваш пароль и автоматически вводит его при коннекте на сервер."); imgui.Spacing()

                    if st.cfg_auto_alogin[0] then
                        imgui.Indent(45); imgui.PushItemWidth(150)
                        imgui.InputText("##alogin_pass", st.cfg_alogin_pass, ffi.sizeof(st.cfg_alogin_pass), imgui.InputTextFlags.Password)
                        imgui.PopItemWidth(); imgui.SameLine()
                        if imgui.Button("Сохранить") then saveConfig(); sampAddChatMessage(u8:decode("[GibsonHelper] Пароль сохранен в конфиг."), 0xFF0000) end
                        imgui.Unindent(45)
                    end
                    imgui.EndChild(); imgui.SameLine()

                    imgui.BeginChild("SettingsHotkeys", imgui.ImVec2(0, 0), false)
                    imgui.Text("Горячие клавиши")
                    imgui.Separator(); imgui.Spacing()

                    DrawHotkeyBtn("btn_menu",   "Меню Gibson Helper", st.hk_menu)
                    DrawHotkeyBtn("btn_report", "Авто-Репорт",        st.hk_report)
                    DrawHotkeyBtn("btn_rules",  "Правила сервера",    st.hk_rules)
                    DrawHotkeyBtn("btn_ghetto", "Гетто-зоны (Скоро)", st.hk_ghetto)
                    DrawHotkeyBtn("btn_invis",  "Невидимка",          st.hk_invis)

                    imgui.Spacing(); imgui.Spacing()
                    CustomToggle("RGB Chroma Mode", _G.cfg_chroma, "Заставляет интерфейс плавно переливаться всеми цветами радуги.")
                    imgui.Spacing(); imgui.Text("Стиль интерфейса"); imgui.Separator(); imgui.Spacing()

                    local palette = {
                        {imgui.ImVec4(0.70, 0.15, 0.15, 1.0), "Красный"}, {imgui.ImVec4(0.85, 0.75, 0.10, 1.0), "Желтый"},
                        {imgui.ImVec4(0.20, 0.80, 0.20, 1.0), "Зеленый"}, {imgui.ImVec4(0.15, 0.75, 0.85, 1.0), "Голубой"},
                        {imgui.ImVec4(0.15, 0.35, 0.90, 1.0), "Синий"}, {imgui.ImVec4(0.65, 0.20, 0.90, 1.0), "Фиолетовый"}
                    }
                    for i, color_data in ipairs(palette) do
                        local color, p, radius = color_data[1], imgui.GetCursorScreenPos(), 10
                        imgui.InvisibleButton("color_"..i, imgui.ImVec2(radius * 2, radius * 2))
                        if imgui.IsItemClicked() then st.current_theme[0] = i - 1; saveConfig(); ApplyTheme(st.current_theme[0]) end
                        if imgui.IsItemHovered() then imgui.SetTooltip(color_data[2]) end

                        local draw_list = imgui.GetWindowDrawList()
                        draw_list:AddCircleFilled(imgui.ImVec2(p.x + radius, p.y + radius), radius, imgui.GetColorU32Vec4(color))
                        if st.current_theme[0] == i - 1 then draw_list:AddCircle(imgui.ImVec2(p.x + radius, p.y + radius), radius + 3, imgui.GetColorU32Vec4(imgui.ImVec4(1,1,1,1)), 16, 2.0) end
                        if i < #palette then imgui.SameLine() end
                    end
                    imgui.EndChild()

                elseif st.activeTab[0] == 2 then
                    imgui.BeginChild("AdminFeatures", imgui.ImVec2(0, 0), false)
                    imgui.Text("Админ ПО (Функции)")
                    imgui.Separator(); imgui.Spacing()

                    CustomToggle("Clickwarp", st.cfg_adm_clickwarp)
                    imgui.SameLine(nil, 20)
                    imgui.TextDisabled("(Активация: Колесико мыши | В авто: ПКМ + ЛКМ)")
                    imgui.Spacing()

                    CustomToggle("Включить Airbrake (v7)", st.cfg_ab_state)
                    imgui.SameLine(nil, 20)
                    imgui.TextDisabled("(Активация на Правый Shift в игре)")
                    imgui.Spacing()
                    
                    if st.cfg_ab_state[0] then
                        imgui.Indent(20)
                        imgui.Text("Локальная скорость:")
                        imgui.PushItemWidth(150)
                        if imgui.SliderFloat("Персонаж##local", st.cfg_ab_speed_player, 0.1, 5.0) then saveConfig() end; imgui.SameLine()
                        if imgui.SliderFloat("Машина##local", st.cfg_ab_speed_vehicle, 0.1, 5.0) then saveConfig() end; imgui.SameLine()
                        if imgui.SliderFloat("Пассажир##local", st.cfg_ab_speed_passenger, 0.1, 5.0) then saveConfig() end
                        imgui.Spacing()
                        imgui.Text("Скорость синхронизации (пакеты):")
                        if imgui.SliderFloat("Персонаж##sync", st.cfg_ab_sync_player, 0.1, 5.0) then saveConfig() end; imgui.SameLine()
                        if imgui.SliderFloat("Машина##sync", st.cfg_ab_sync_vehicle, 0.1, 5.0) then saveConfig() end; imgui.SameLine()
                        if imgui.SliderFloat("Пассажир##sync", st.cfg_ab_sync_passenger, 0.1, 5.0) then saveConfig() end
                        imgui.PopItemWidth(); imgui.Unindent(20)
                    end
                    imgui.Spacing()

                    CustomToggle("GM Car (Бессмертие авто)", st.cfg_adm_gm_car)
                    imgui.SameLine(nil, 20)
                    imgui.TextDisabled("(На визуал он не работает | DEL - переворот)")
                    imgui.Spacing()

                    CustomToggle("Спидхак на авто / поезд", st.cfg_adm_speedhack)
                    if st.cfg_adm_speedhack[0] then
                        imgui.Indent(20)
                        imgui.PushItemWidth(180)
                        
                        local input_key_buf = imgui.new.char[64](ffi.string(st.sh_key))
                        if imgui.InputText("Ключ активации##sh", input_key_buf, 64, imgui.InputTextFlags.EnterReturnsTrue) then
                            local entered_name = ffi.string(input_key_buf)
                            if vkeys.name_to_id(entered_name, false) ~= nil then
                                ffi.copy(st.sh_key, entered_name)
                                saveConfig()
                            else
                                ffi.copy(st.sh_key, "<invalid key>")
                            end
                        end

                        if imgui.SliderFloat("Mult.##sh", st.sh_mult, 0.001, 100.0) then saveConfig() end
                        imgui.SameLine(); imgui.TextDisabled("(реком. 5.915)")

                        if imgui.SliderFloat("Limit##sh", st.sh_limit, 0.01, 1000.0) then saveConfig() end
                        imgui.SameLine(); imgui.TextDisabled("(реком. 5.386)")

                        if imgui.SliderFloat("Time step##sh", st.sh_timestep, 0.0, 1.0) then saveConfig() end
                        imgui.SameLine(); imgui.TextDisabled("(реком. 0.032)")

                        if imgui.Checkbox("Safe train speed##sh", st.sh_safe_train) then saveConfig() end

                        imgui.PopItemWidth()
                        imgui.Unindent(20)
                    end
                    imgui.Spacing()

                    CustomToggle("Трейсера пуль (BulletTrack)", st.cfg_bt_active)
                    if st.cfg_bt_active[0] then
                        imgui.Indent(20)
                        
                        CustomToggle("Отображать ID над трейсером", st.cfg_bt_show_id)
                        imgui.Spacing()

                        if imgui.ColorEdit3("Цвет: Игроки (Ped)", st.cfg_bt_color_ped) then saveConfig() end
                        if imgui.ColorEdit3("Цвет: Транспорт (Car)", st.cfg_bt_color_car) then saveConfig() end
                        if imgui.ColorEdit3("Цвет: Объекты/Остальное", st.cfg_bt_color_obj) then saveConfig() end
                        
                        imgui.PushItemWidth(180)
                        if imgui.SliderFloat("Толщина линий", st.cfg_bt_thickness, 1.0, 10.0) then saveConfig() end
                        if imgui.SliderFloat("Время показа (сек)", st.cfg_bt_time, 0.5, 10.0) then saveConfig() end
                        imgui.PopItemWidth()

                        imgui.Unindent(20)
                    end
                    imgui.Spacing()

                    CustomToggle("Невидимка (Invis)", st.cfg_adm_invis)
                    imgui.SameLine(nil, 20)
                    imgui.TextDisabled("(Активация: Горячая клавиша из Настроек)")
                    imgui.Spacing()

                    CustomToggle("Skeletal WallHack", st.cfg_wh_state)
                    if st.cfg_wh_state[0] then
                        imgui.Indent(20)
                        imgui.Text("Настройки отображения:")
                        if imgui.RadioButtonBool("Показывать всё", st.cfg_wh_mode[0] == 0) then st.cfg_wh_mode[0] = 0; saveConfig() end
                        if imgui.RadioButtonBool("Только кости (bones)", st.cfg_wh_mode[0] == 1) then st.cfg_wh_mode[0] = 1; saveConfig() end
                        if imgui.RadioButtonBool("Только ники (names)", st.cfg_wh_mode[0] == 2) then st.cfg_wh_mode[0] = 2; saveConfig() end
                        
                        imgui.Spacing()
                        imgui.PushItemWidth(180)
                        if imgui.SliderFloat("Дистанция", st.cfg_wh_distance, 10.0, 1000.0) then saveConfig() end
                        if imgui.SliderFloat("Высота ника", st.cfg_wh_name_height, 0.0, 5.0) then saveConfig() end
                        if imgui.SliderFloat("Толщина костей", st.cfg_wh_bone_thick, 1.0, 10.0) then saveConfig() end
                        imgui.PopItemWidth()

                        imgui.Unindent(20)
                    end
                    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                    CustomToggle("NoBike (Антипадение)", st.nb_active)

                    imgui.EndChild()

                elseif st.activeTab[0] == 3 then
                    imgui.Text("Настройки Авто-Репорта")
                    imgui.Separator(); imgui.Spacing()
                    CustomToggle("Автоматически открывать окно при новом репорте", st.cfg_auto_open_report)
                    imgui.Spacing(); imgui.Spacing()

                    imgui.Text("Настройка шаблонов ответов")
                    imgui.SameLine(imgui.GetWindowWidth() - 180)
                    if imgui.Button("+ Добавить шаблон") then table.insert(report_tpls, {name = "Новая кнопка", text = "Введите текст ответа"}); saveConfig() end
                    imgui.Separator(); imgui.Spacing()

                    for i, t in ipairs(report_tpls) do
                        local bufName = imgui.new.char[256](t.name)
                        local bufText = imgui.new.char[256](t.text)
                        imgui.PushItemWidth(130)
                        if imgui.InputText("##Name_"..i, bufName, ffi.sizeof(bufName)) then t.name = ffi.string(bufName); saveConfig() end
                        imgui.PopItemWidth(); imgui.SameLine()
                        imgui.PushItemWidth(380)
                        if imgui.InputText("##Text_"..i, bufText, ffi.sizeof(bufText)) then t.text = ffi.string(bufText); saveConfig() end
                        imgui.PopItemWidth(); imgui.SameLine()
                        if imgui.Button("X##"..i) then table.remove(report_tpls, i); saveConfig() end
                    end

                elseif st.activeTab[0] == 4 then
                    imgui.BeginChild("AutoGiveContent", imgui.ImVec2(0, 0), false)
                    imgui.PushItemWidth(350)

                    local chats = {"/aad", "/o"}
                    local current_chat_preview = chats[st.auto_give_chat_idx[0] + 1] or chats[1]
                    if imgui.BeginCombo("##auto_give_chat", current_chat_preview) then
                        for i, chat_name in ipairs(chats) do
                            local is_selected = (st.auto_give_chat_idx[0] == i - 1)
                            if imgui.Selectable(chat_name, is_selected) then st.auto_give_chat_idx[0] = i - 1 end
                            if is_selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.SameLine(); imgui.Text("Чат")

                    imgui.InputText("##auto_give_word", st.auto_give_word_buf, ffi.sizeof(st.auto_give_word_buf))
                    imgui.SameLine(); imgui.Text("Слово для /rep")

                    local current_prize_preview = prizes[st.auto_give_prize_idx[0] + 1] or prizes[1]
                    if imgui.BeginCombo("##auto_give_prize", current_prize_preview) then
                        for i, prize_name in ipairs(prizes) do
                            local is_selected = (st.auto_give_prize_idx[0] == i - 1)
                            if imgui.Selectable(prize_name, is_selected) then st.auto_give_prize_idx[0] = i - 1 end
                            if is_selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.SameLine(); imgui.Text("Приз")

                    if st.auto_give_prize_idx[0] < 16 then
                        imgui.InputText("##auto_give_count", st.auto_give_count_buf, ffi.sizeof(st.auto_give_count_buf))
                        imgui.SameLine(); imgui.Text("Количество")
                    end

                    imgui.PopItemWidth()
                    imgui.Spacing()
                    imgui.TextColored(imgui.ImVec4(1.0, 0.2, 0.2, 1.0), "Пример: 5k / 5kk / 5kkk")
                    imgui.Spacing()

                    if not st.auto_give_active then
                        if imgui.Button("Начать раздачу", imgui.ImVec2(150, 30)) then
                            local word = ffi.string(st.auto_give_word_buf)
                            local count = ffi.string(st.auto_give_count_buf)
                            if word ~= "" then
                                st.auto_give_active = true
                                st.auto_give_word_saved = word
                                st.auto_give_chat_saved = chats[st.auto_give_chat_idx[0] + 1]
                                st.auto_give_prize_idx_saved = st.auto_give_prize_idx[0]
                                st.auto_give_count_saved = count
                                
                                local p_name = prizes[st.auto_give_prize_idx_saved + 1]
                                lua_thread.create(function()
                                    if st.auto_give_prize_idx_saved < 16 then
                                        sampSendChat(u8:decode(string.format("%s РАЗДАЧА | Первый, кто напишет в /report %s, получит %s в количестве %s.", st.auto_give_chat_saved, st.auto_give_word_saved, p_name, st.auto_give_count_saved)))
                                    else
                                        sampSendChat(u8:decode(string.format("%s РАЗДАЧА | Первый, кто напишет в /report %s, получит %s.", st.auto_give_chat_saved, st.auto_give_word_saved, p_name)))
                                    end
                                end)
                            end
                        end
                    else
                        if imgui.Button("Остановить раздачу", imgui.ImVec2(150, 30)) then
                            st.auto_give_active = false
                        end
                    end

                    imgui.EndChild()

                elseif st.activeTab[0] == 5 then
                    imgui.BeginChild("MPContent", imgui.ImVec2(0, 0), false)
                    imgui.Text("Управление мероприятиями")
                    imgui.Separator(); imgui.Spacing()

                    imgui.PushItemWidth(350)
                    
                    local chats = {"/aad", "/o"}
                    local current_chat_preview = chats[st.mp_chat_idx[0] + 1] or chats[1]
                    if imgui.BeginCombo("##mp_chat", current_chat_preview) then
                        for i, chat_name in ipairs(chats) do
                            local is_selected = (st.mp_chat_idx[0] == i - 1)
                            if imgui.Selectable(chat_name, is_selected) then st.mp_chat_idx[0] = i - 1 end
                            if is_selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.SameLine(); imgui.Text("Чат")

                    local current_mp_preview = mp_list[st.mp_list_idx[0] + 1] or mp_list[1]
                    if imgui.BeginCombo("##mp_list", current_mp_preview) then
                        for i, mp_name in ipairs(mp_list) do
                            local is_selected = (st.mp_list_idx[0] == i - 1)
                            if imgui.Selectable(mp_name, is_selected) then st.mp_list_idx[0] = i - 1 end
                            if is_selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.SameLine(); imgui.Text("Список мероприятий")

                    imgui.InputText("##mp_prize", st.mp_prize_buf, ffi.sizeof(st.mp_prize_buf))
                    imgui.SameLine(); imgui.Text("Приз мероприятия")
                    
                    imgui.PopItemWidth()
                    imgui.Spacing(); imgui.Spacing()

                    if imgui.Button("Начать мероприятие", imgui.ImVec2(200, 35)) then
                        local chat_cmd = chats[st.mp_chat_idx[0] + 1]
                        local mp_name = mp_list[st.mp_list_idx[0] + 1]
                        local mp_prize = ffi.string(st.mp_prize_buf)

                        lua_thread.create(function()
                            sampSendChat(u8:decode(string.format("%s MP | Уважаемые игроки, минуточку внимания.", chat_cmd)))
                            wait(1500)
                            sampSendChat(u8:decode(string.format("%s MP | Сейчас пройдет мероприятие \"%s\". Приз: %s.", chat_cmd, mp_name, mp_prize)))
                            wait(1500)
                            sampSendChat(u8:decode(string.format("%s MP | После телепорта на мероприятие сразу строимся.", chat_cmd)))
                            wait(1500)
                            sampSendChat("/mp")
                            wait(200) 
                            setVirtualKeyDown(vkeys.VK_RETURN, true)
                            wait(20)
                            setVirtualKeyDown(vkeys.VK_RETURN, false)
                        end)
                    end

                    imgui.EndChild()

                elseif st.activeTab[0] == 6 then
                    imgui.BeginChild("OtborContent", imgui.ImVec2(0, 0), false)
                    imgui.Text("Управление отборами")
                    imgui.Separator(); imgui.Spacing()

                    imgui.PushItemWidth(350)
                    local current_leader_preview = leader_list[st.otbor_list_idx[0] + 1] or leader_list[1]
                    if imgui.BeginCombo("##otbor_list", current_leader_preview) then
                        for i, leader_name in ipairs(leader_list) do
                            local is_selected = (st.otbor_list_idx[0] == i - 1)
                            if imgui.Selectable(leader_name, is_selected) then st.otbor_list_idx[0] = i - 1 end
                            if is_selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.SameLine(); imgui.Text("Список Лидеров")
                    imgui.PopItemWidth()
                    
                    imgui.Spacing(); imgui.Spacing()

                    if imgui.Button("Начать отбор", imgui.ImVec2(200, 35)) then
                        local leader_name = leader_list[st.otbor_list_idx[0] + 1]

                        lua_thread.create(function()
                            sampSendChat(u8:decode(string.format("/o ОТБОР | Сейчас пройдет отбор на пост лидера \"%s\".", leader_name)))
                            wait(1500)
                            sampSendChat(u8:decode("/o ОТБОР | Критерии: наличие вк, возраст от 13 лет."))
                            wait(1500)
                            sampSendChat(u8:decode("/o ОТБОР | Все желающие /gomp!"))
                            wait(1500)
                            sampSendChat("/mp")
                            wait(200) 
                            setVirtualKeyDown(vkeys.VK_RETURN, true)
                            wait(20)
                            setVirtualKeyDown(vkeys.VK_RETURN, false)
                        end)
                    end

                    imgui.EndChild()

                elseif st.activeTab[0] == 7 then
                    imgui.BeginChild("MiscContent", imgui.ImVec2(0, 0), false)
                    imgui.Text("Временное Лидерство")
                    imgui.Text("Нажмите на кнопку с названием фракции\nчтобы выдать себе временное лидерство")
                    imgui.Separator(); imgui.Spacing()
                    
                    imgui.TextColored(imgui.ImVec4(1.0, 0.4, 0.4, 1.0), "Самоувольнение:")
                    if imgui.Button("Уволить себя", imgui.ImVec2(200, 35)) then
                        local res, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
                        if res then
                           sampSendChat(u8:decode("/uval " .. myId .. " ПСЖ"))
                        end
                    end
                    
                    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                    imgui.Text("Выдать временное лидерство:")
                    
                    imgui.BeginChild("LeaderButtons", imgui.ImVec2(0, 260), true)
                    imgui.Columns(2, "LeaderColumns", false)
                    
                    local f_col1 = {
                        {"LSPD", 1}, {"ФБР", 2}, {"Army LS", 3}, {"Больница ЛС", 4}, {"LCN", 5},
                        {"Yakuza", 6}, {"Мэрия", 7}, {"Ballas", 12}, {"Vagos", 13}, {"Russia Mafia", 14}
                    }
                    local f_col2 = {
                        {"Grove", 15}, {"Радиоцентр", 16}, {"Aztec", 17}, {"Rifa", 18}, {"Xitman", 23},
                        {"SWAT", 25}, {"АП", 26}, {"RCPD", 27}, {"Outlaws MC", 28}, {"Верховный Суд", 29}
                    }
                    
                    for i=1, 10 do
                        if imgui.Button(f_col1[i][1] .. "##col1_" .. i, imgui.ImVec2(-1, 30)) then
                            sampSendChat("/templeader " .. f_col1[i][2])
                        end
                    end
                    
                    imgui.NextColumn()
                    
                    for i=1, 10 do
                        if imgui.Button(f_col2[i][1] .. "##col2_" .. i, imgui.ImVec2(-1, 30)) then
                            sampSendChat("/templeader " .. f_col2[i][2])
                        end
                    end
                    
                    imgui.Columns(1)
                    imgui.EndChild()

                    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                    imgui.Text("Выдача оружия")
                    imgui.Separator(); imgui.Spacing()

                    imgui.PushItemWidth(250)
                    local current_weapon = weapon_list[st.givegun_weapon_idx[0] + 1] or weapon_list[1]
                    local current_weapon_preview = string.format("%s[id%d]", current_weapon.name, current_weapon.id)
                    if imgui.BeginCombo("##givegun_combo", current_weapon_preview) then
                        for i, w in ipairs(weapon_list) do
                            local is_selected = (st.givegun_weapon_idx[0] == i - 1)
                            local w_label = string.format("%s[id%d]", w.name, w.id)
                            if imgui.Selectable(w_label, is_selected) then
                                st.givegun_weapon_idx[0] = i - 1
                            end
                            if is_selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.SameLine(); imgui.Text("Оружие")

                    imgui.InputText("##givegun_ammo", st.givegun_ammo_buf, ffi.sizeof(st.givegun_ammo_buf))
                    imgui.SameLine(); imgui.Text("Количество патрон")
                    imgui.PopItemWidth()

                    imgui.Spacing()
                    if imgui.Button("Выдать оружие", imgui.ImVec2(200, 35)) then
                        local res, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
                        if res then
                            local w = weapon_list[st.givegun_weapon_idx[0] + 1]
                            local ammo = ffi.string(st.givegun_ammo_buf)
                            if w and ammo ~= "" then
                                sampSendChat(string.format("/givegun %d %d %s", myId, w.id, ammo))
                            end
                        end
                    end

                    -- === СПАВН ТРАНСПОРТА ===
                    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                    imgui.Text("Спавн транспорта")
                    imgui.Separator(); imgui.Spacing()

                    imgui.PushItemWidth(250)
                    local current_veh = vehicle_list[st.spawnveh_idx[0] + 1] or vehicle_list[1]
                    local current_veh_preview = string.format("%s[%d]", current_veh.name, current_veh.id)
                    if imgui.BeginCombo("Список транспорта##spawnveh_combo", current_veh_preview) then
                        for i, veh in ipairs(vehicle_list) do
                            local is_selected = (st.spawnveh_idx[0] == i - 1)
                            local veh_label = string.format("%s[%d]", veh.name, veh.id)
                            if imgui.Selectable(veh_label, is_selected) then
                                st.spawnveh_idx[0] = i - 1
                            end
                            if is_selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.PopItemWidth()

                    imgui.Spacing()
                    -- Цвет №1, Цвет №2, toggle С турбо?, toggle Временная? в одну строчку
                    imgui.PushItemWidth(60)
                    imgui.InputText("##spawnveh_c1", st.spawnveh_color1, ffi.sizeof(st.spawnveh_color1))
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.Text("Цвет №1")
                    imgui.SameLine(nil, 15)

                    imgui.PushItemWidth(60)
                    imgui.InputText("##spawnveh_c2", st.spawnveh_color2, ffi.sizeof(st.spawnveh_color2))
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.Text("Цвет №2")
                    imgui.SameLine(nil, 15)

                    imgui.Checkbox("С турбо?", st.spawnveh_turbo)
                    imgui.SameLine(nil, 15)
                    imgui.Checkbox("Временная?", st.spawnveh_temp)

                    imgui.Spacing()
                    if imgui.Button("Спавнить транспорт", imgui.ImVec2(200, 35)) then
                        local v = vehicle_list[st.spawnveh_idx[0] + 1]
                        local c1 = ffi.string(st.spawnveh_color1)
                        local c2 = ffi.string(st.spawnveh_color2)
                        local turbo = st.spawnveh_turbo[0] and "1" or "0"
                        local temp = st.spawnveh_temp[0] and "1" or "0"
                        if v then
                            sampSendChat(string.format("/veh %d %s %s %s %s", v.id, c1, c2, turbo, temp))
                        end
                    end

                    -- === ВЫДАЧА СКИНА ===
                    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                    imgui.Text("Выдача скина")
                    imgui.Separator(); imgui.Spacing()

                    imgui.PushItemWidth(250)
                    
                    -- Ищем превью текущего выбранного скина для отображения в закрытом комбо-боксе
                    local current_skin_preview = "Carl 'CJ' Johnson [0]"
                    for _, cat in ipairs(skin_categories) do
                        for _, s in ipairs(cat.skins) do
                            if s.id == st.setskin_id[0] then
                                current_skin_preview = string.format("%s [%d]", s.name, s.id)
                                break
                            end
                        end
                    end

                    --- Рендер комбо-бокса с категориями
                    if imgui.BeginCombo("##setskin_combo", current_skin_preview) then
                        for _, cat in ipairs(skin_categories) do
                            -- Берем цвет из таблицы или ставим серый по умолчанию, если его там нет
                            local cat_color = cat.color or imgui.ImVec4(0.5, 0.5, 0.5, 1.0)
                            imgui.TextColored(cat_color, cat.name)
                            imgui.Separator()
                            
                            for _, s in ipairs(cat.skins) do
                                local is_selected = (st.setskin_id[0] == s.id)
                                if imgui.Selectable(string.format("  %s [%d]", s.name, s.id), is_selected) then
                                    st.setskin_id[0] = s.id
                                end
                                if is_selected then
                                    imgui.SetItemDefaultFocus()
                                end
                            end
                            imgui.Spacing()
                        end
                        imgui.EndCombo()
                    end
                    imgui.PopItemWidth()

                    -- Галочка и ввод ID в одну строчку
                    imgui.SameLine(nil, 15)
                    imgui.Checkbox("Выдать себе", st.setskin_self)

                    if not st.setskin_self[0] then
                        imgui.SameLine(nil, 15)
                        imgui.PushItemWidth(80)
                        imgui.InputText("ID игрока##setskin_id", st.setskin_id_buf, ffi.sizeof(st.setskin_id_buf))
                        imgui.PopItemWidth()
                    end

                    -- Кнопка выдачи
                    imgui.Spacing()
                    if imgui.Button("Выдать скин", imgui.ImVec2(200, 35)) then
                        local target_id = ""
                        if st.setskin_self[0] then
                            local res, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
                            if res then target_id = tostring(myId) end
                        else
                            target_id = ffi.string(st.setskin_id_buf)
                        end

                        if target_id ~= "" then
                            sampSendChat(string.format("/setskin %s %d", target_id, st.setskin_id[0]))
                        end
                    end

                    imgui.EndChild()

                elseif st.activeTab[0] == 8 then
                    -- === Вкладка Правила Сервера ===
                    imgui.BeginChild("RulesContent", imgui.ImVec2(0, 0), false)
                    imgui.Text("Свод Правил")
                    imgui.SameLine(imgui.GetWindowWidth() - 250)
                    imgui.PushItemWidth(230)
                    imgui.InputText("Поиск по правилам", st.search_rules_buf, ffi.sizeof(st.search_rules_buf))
                    imgui.PopItemWidth()
                    imgui.Separator(); imgui.Spacing()

                    local search_query = u8:decode(ffi.string(st.search_rules_buf)):lower()

                    for i, rule in ipairs(rules_list) do
                        local ui_text = rule.ui
                        local content = rules_content[rule.file] or "Пусто..."
                        
                        local match_title = u8:decode(ui_text):lower():find(search_query, 1, true)
                        local match_content = u8:decode(content):lower():find(search_query, 1, true)

                        if search_query == "" or match_title or match_content then
                            if imgui.CollapsingHeader("ANGER | " .. ui_text) then
                                imgui.Spacing()
                                imgui.PushTextWrapPos(imgui.GetWindowWidth() - 20)
                                imgui.TextUnformatted(content)
                                imgui.PopTextWrapPos()
                                
                                imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                                if imgui.Button("Обновить файл##" .. i) then
                                    local path = getWorkingDirectory() .. "\\GibsonHelper\\" .. u8:decode(rule.file) .. ".txt"
                                    local f = io.open(path, "r")
                                    if f then
                                        rules_content[rule.file] = u8(f:read("*a"))
                                        f:close()
                                    end
                                end
                                imgui.SameLine()
                                imgui.TextDisabled("(Отредактируй txt файл в папке GibsonHelper и нажми чтобы обновить текст)")
                                imgui.Spacing()
                            end
                        end
                    end

                    imgui.EndChild()
                elseif st.activeTab[0] == 9 then
                    -- === Вкладка Авто чек нормы ===
                    imgui.BeginChild("NormCheckContent", imgui.ImVec2(0, 0), false)
                    imgui.Text("Автоматическая проверка нормы")
                    imgui.Separator(); imgui.Spacing()
                
                    imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "ВНИМАНИЕ: Окна интерфейса ломают цветные эмодзи.")
                    imgui.Text("Чтобы сохранить смайлики, скопируй список (Ctrl+C) и нажми кнопку ниже:")
                    
                    if not st.norm_is_checking then
                        -- КНОПКА ДЛЯ ИДЕАЛЬНОЙ РАБОТЫ
                        if imgui.Button("Проверить ИЗ БУФЕРА ОБМЕНА (Сохраняет смайлы)", imgui.ImVec2(370, 40)) then
                            startNormCheck(true)
                        end
                    else
                        imgui.Button(string.format("Проверка... (%d / %d)", st.norm_progress[0], st.norm_total[0]), imgui.ImVec2(370, 40))
                    end
                
                    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                    
                    imgui.Text("ИЛИ вставь пустой список вручную (смайлы станут '?'):")
                    imgui.InputTextMultiline("##norm_input", st.norm_input_buf, ffi.sizeof(st.norm_input_buf), imgui.ImVec2(-1, 80))
                    
                    if not st.norm_is_checking then
                        if imgui.Button("Проверить из окна", imgui.ImVec2(200, 30)) then
                            if ffi.string(st.norm_input_buf) ~= "" then
                                startNormCheck(false)
                            end
                        end
                    end
                    
                    imgui.Spacing()
                    imgui.Text("Предпросмотр результата:")
                    imgui.InputTextMultiline("##norm_output", st.norm_output_buf, ffi.sizeof(st.norm_output_buf), imgui.ImVec2(-1, 100), imgui.InputTextFlags.ReadOnly)
                
                    imgui.EndChild()
                elseif st.activeTab[0] == 10 then
                    -- === Вкладка Авторы ===
                    imgui.BeginChild("AuthorsContent", imgui.ImVec2(0, 0), false)
                    imgui.Text("Авторы скрипта")
                    imgui.Separator(); imgui.Spacing()
                    
                    imgui.TextWrapped("Хелпер создавала команда великолепных разработчиков: Чингисхан, стоящий на светофоре Mac Traver и Gemini")
                    imgui.TextWrapped("связь - https://vk.ru/ldmnona")
                    
                    imgui.EndChild()
                end

                imgui.EndChild()
                imgui.PopStyleVar()
                imgui.Columns(1); imgui.End()
            end
        end
    end
)

-- === ОБРАБОТКА ДИАЛОГОВ И СОБЫТИЙ SAMP ===
function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    local clean_title = u8(title):gsub("{%x+}", "")
    
    -- ЛОВИМ ДИАЛОГ СТАТИСТИКИ
    if st.norm_is_checking then
        if clean_title:find("Статистика администратора") then
            local clean_text = u8(text):gsub("{%x+}", "")
            -- Парсим часы и минуты из диалога
            local h, m = clean_text:match("Онлайн за сегодня:%s*(%d+)%s*час%.%s*(%d+)%s*мин")
            
            if h and m then
                local h_n, m_n = tonumber(h), tonumber(m)
                local time_str = string.format("%d %s %d %s", h_n, getDeclension(h_n, "час", "часа", "часов"), m_n, getDeclension(m_n, "минута", "минуты", "минут"))
                st.norm_current_result = time_str
            else
                st.norm_current_result = "ошибка парсинга"
            end
            
            -- Скрываем диалог (имитируем нажатие "Закрыть")
            sampSendDialogResponse(dialogId, 1, 0, "")
            return false
            
        elseif clean_title:find("Ошибка") then
            st.norm_current_result = "аккаунт не найден"
            sampSendDialogResponse(dialogId, 1, 0, "")
            return false
        end
    end
    
    if st.cfg_auto_alogin[0] and clean_title:find("Доступ к админ%-панели") then
        local my_pass = ffi.string(st.cfg_alogin_pass)
        if my_pass ~= "" then sampSendDialogResponse(dialogId, 1, 0, my_pass); return false
        else sampAddChatMessage(u8:decode("[GibsonHelper] Ошибка: Пароль пуст. Введите его в настройках (/amenu)"), 0xFF0000) end
    end

    if st.pending_object_dialog and clean_title:find("Выдача временного аксессуара") then
        sampSendDialogResponse(dialogId, 1, st.pending_object_dialog.expected_listitem, "")
        st.pending_object_dialog = nil
        return false 
    end
end

function sampev.onServerMessage(color, text)
    local text_utf8 = u8(text); local clean_text = text_utf8:gsub("{%x+}", "")
    
    -- БЫСТРЫЙ ОТЛОВ ОФФЛАЙНА ДЛЯ ПРОВЕРКИ НОРМЫ
    if st.norm_is_checking then
        local t = clean_text:lower()
        if t:find("не найден") or t:find("не авторизован") or t:find("не в сети") then
            st.norm_current_result = "аккаунт не найден"
            return false -- Блокируем вывод в чат, чтобы не засорять экран
        end
    end
    
    -- Добавили ^%s* в начало проверки. 
    -- Теперь скрипт ловит текст, ТОЛЬКО если строка начинается с "Репорт от", игнорируя админ-чат.
    local repName, repId, repMsg = clean_text:match("^%s*Репорт от (.-)%[(%d+)%]: (.*)")
    
    if repName and repId then
        -- Никаких проверок на дубликаты, сразу создаем репорт
        local new_report = {id = repId, name = repName, text = repMsg}
        
        if st.auto_give_active then
            local target_word = st.auto_give_word_saved
            if repMsg:find(target_word, 1, true) then
                st.auto_give_active = false 

                lua_thread.create(function()
                    sampSendChat(u8:decode(string.format("%s РАЗДАЧА | Игрок %s[%s] первым написал верное слово и выиграл приз!", st.auto_give_chat_saved, repName, repId)))
                    wait(1000) 
                    
                    if st.auto_give_prize_idx_saved < 16 then
                        sampSendChat(u8:decode(string.format("/setstat %s %d %s", repId, st.auto_give_prize_idx_saved + 1, st.auto_give_count_saved)))
                    else
                        st.pending_object_dialog = { expected_listitem = st.auto_give_prize_idx_saved - 16 }
                        sampSendChat(string.format("/object %s", repId))
                    end
                end)
            end
        end

        if st.active_report == nil then
            st.active_report = new_report
            if st.cfg_auto_open_report[0] then st.reportWindow[0] = true else sampAddChatMessage(u8:decode("[GibsonHelper] Поступил новый репорт! (Используйте хоткей для открытия)"), 0xFFFF00) end
        else
            table.insert(st.report_queue, new_report); if st.cfg_auto_open_report[0] then st.reportWindow[0] = true end
        end
    end

    if st.cfg_agm_togphone[0] then
        local adminName = clean_text:match("%[ALogin%] (.-)%[%d+%] авторизовался как администратор")
        if adminName then
            local result, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
            if result and adminName == sampGetPlayerNickname(myId) then
                lua_thread.create(function() wait(1000); sampSendChat("/agm"); wait(1000); sampSendChat("/togphone"); wait(500); sampAddChatMessage(u8:decode("[GibsonHelper] Режим бога и выключение телефона активированы."), 0x00FF00) end)
                return 0xFF00FF00, u8:decode("Вы успешно авторизовались!")
            end
        end
    end
end

local function getTracerColor(tType)
    if tType == 1 or tType == 4 then return join_argb(255, st.cfg_bt_color_ped[0]*255, st.cfg_bt_color_ped[1]*255, st.cfg_bt_color_ped[2]*255) end
    if tType == 2 then return join_argb(255, st.cfg_bt_color_car[0]*255, st.cfg_bt_color_car[1]*255, st.cfg_bt_color_car[2]*255) end
    return join_argb(255, st.cfg_bt_color_obj[0]*255, st.cfg_bt_color_obj[1]*255, st.cfg_bt_color_obj[2]*255)
end

function sampev.onSendBulletSync(data)
    if not st.cfg_bt_active[0] then return end 
    local ox, oy, oz = data.origin.x, data.origin.y, data.origin.z
    local tx, ty, tz = data.target.x, data.target.y, data.target.z
    
    if tx == 0 and ty == 0 and tz == 0 then return end
    
    if ox == 0 and oy == 0 and oz == 0 then
        local mx, my, mz = getCharCoordinates(PLAYER_PED)
        ox, oy, oz = mx, my, mz + 0.7 
    end
    
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    table.insert(st.tracers, { ox = ox, oy = oy, oz = oz, tx = tx, ty = ty, tz = tz, time = os.clock() + st.cfg_bt_time[0], color = getTracerColor(data.targetType), id = myId }) 
end

function sampev.onBulletSync(playerId, data)
    if not st.cfg_bt_active[0] then return end
    local ox, oy, oz = data.origin.x, data.origin.y, data.origin.z
    local tx, ty, tz = data.target.x, data.target.y, data.target.z
    
    if tx == 0 and ty == 0 and tz == 0 then return end
    
    if ox == 0 and oy == 0 and oz == 0 then
        local res, ped = sampGetCharHandleBySampPlayerId(playerId)
        if res and doesCharExist(ped) then
            local mx, my, mz = getCharCoordinates(ped)
            ox, oy, oz = mx, my, mz + 0.7
        end
    end
    
    table.insert(st.tracers, { ox = ox, oy = oy, oz = oz, tx = tx, ty = ty, tz = tz, time = os.clock() + st.cfg_bt_time[0], color = getTracerColor(data.targetType), id = playerId }) 
end

-- === Вспомогательные функции для анти-рванки ===
local function getSpeedFromVector3D(vec)
    return math.sqrt(vec.x ^ 2 + vec.y ^ 2 + vec.z ^ 2)
end

local function getDistanceFrom(vec)
    local x, y, z = getCharCoordinates(PLAYER_PED)
    return math.sqrt((vec.x - x) ^ 2 + (vec.y - y) ^ 2 + (vec.z - z) ^ 2)
end

-- === АНТИ-ЧИТ ПРОВЕРКИ ===
local rvanka_warn_time = {}
local weap_warn_time = {}
local cheat_weapons = {
    [35] = "RPG", 
    [36] = "HS Rocket", 
    [37] = "Flamethrower", 
    [38] = "Minigun", 
    [39] = "Satchel"
}

-- Общая функция вывода варнинга на рванку
local function warning_rvanka(id, rtype)
    if rvanka_warn_time[id] and os.clock() - rvanka_warn_time[id] < 2.0 then
        return
    end
    rvanka_warn_time[id] = os.clock()
    local pnick = sampIsPlayerConnected(id) and sampGetPlayerNickname(id) or "Unknown"
    local plvl = sampIsPlayerConnected(id) and sampGetPlayerScore(id) or 0
    local pping = sampIsPlayerConnected(id) and sampGetPlayerPing(id) or 0
    
    sampAddChatMessage(u8:decode(string.format('{FFFF00}[GibsonHelper]{FFFFFF} %s [ID: %d LVL: %d PING: %d] возможно использует %s рванку', pnick, id, plvl, pping, rtype)), -1)
end

function sampev.onPlayerSync(id, data)
    local current_time = os.clock()

    -- Проверка на читерское оружие
    if st.cfg_warn_cheat_weap[0] then
        local w = data.weapon
        if cheat_weapons[w] then
            if not weap_warn_time[id] or (current_time - weap_warn_time[id]) > 15.0 then
                weap_warn_time[id] = current_time
                local name = sampGetPlayerNickname(id) or "Unknown"
                local w_name = cheat_weapons[w]
                sampAddChatMessage(u8:decode(string.format("{FFFF00}[GibsonHelper]{FFFFFF} %s[%d] возможно выдает оружие через чит (%s).", name, id, w_name)), -1)
            end
        end
    end

    -- Проверка на рванку с ног (ONFOOT)
    if st.cfg_warn_rvanka[0] then
        if getSpeedFromVector3D(data.moveSpeed) >= 0.7 and getDistanceFrom(data.position) <= 4.0 then
            warning_rvanka(id, "onfoot")
            return false -- Блокируем пакет, чтобы тебя не снесло
        end
    end
end

function sampev.onVehicleSync(id, veh, data)
    -- Проверка на рванку в машине (INCAR)
    if st.cfg_warn_rvanka[0] then
        if getSpeedFromVector3D(data.moveSpeed) >= 1.0 and getDistanceFrom(data.position) <= 4.0 then
            local resvh, vehHandle = sampGetCarHandleBySampVehicleId(veh)
            if not isCharInCar(PLAYER_PED, vehHandle) then
                warning_rvanka(id, "incar")
                return false -- Блокируем пакет
            end
        end
    end
end

function sampev.onUnoccupiedSync(id, data)
    -- Проверка на рванку пустыми авто (UNOCCUPIED)
    if st.cfg_warn_rvanka[0] then
        if getDistanceFrom(data.position) <= 100.0 then
            if getSpeedFromVector3D(data.moveSpeed) >= 0.5 then
                warning_rvanka(id, "unoccupied")
            end
            return false -- Блокируем пакет
        end
    end
end

function samp_create_sync_data(arg_4_0, arg_4_1)
    local var_4_0 = require("ffi")
    local var_4_1 = require("sampfuncs")
    local var_4_2 = require("samp.raknet")

    arg_4_1 = arg_4_1 or true

    local var_4_3 = ( {
        player = {
            "PlayerSyncData",
            var_4_2.PACKET.PLAYER_SYNC,
            sampStorePlayerOnfootData
        },
        vehicle = {
            "VehicleSyncData",
            var_4_2.PACKET.VEHICLE_SYNC,
            sampStorePlayerIncarData
        },
        passenger = {
            "PassengerSyncData",
            var_4_2.PACKET.PASSENGER_SYNC,
            sampStorePlayerPassengerData
        },
        aim = {
            "AimSyncData",
            var_4_2.PACKET.AIM_SYNC,
            sampStorePlayerAimData
        },
        trailer = {
            "TrailerSyncData",
            var_4_2.PACKET.TRAILER_SYNC,
            sampStorePlayerTrailerData
        },
        unoccupied = {
            "UnoccupiedSyncData",
            var_4_2.PACKET.UNOCCUPIED_SYNC
        },
        bullet = {
            "BulletSyncData",
            var_4_2.PACKET.BULLET_SYNC
        },
        spectator = {
            "SpectatorSyncData",
            var_4_2.PACKET.SPECTATOR_SYNC
        }
    })[arg_4_0]
    local var_4_4 = "struct " .. var_4_3[1]
    local var_4_5 = var_4_0.new(var_4_4, {})
    local var_4_6 = tonumber(var_4_0.cast("uintptr_t", var_4_0.new(var_4_4 .. "*", var_4_5)))

    if arg_4_1 then
        local var_4_7 = var_4_3[3]

        if var_4_7 then
            local var_4_8
            local var_4_9

            if arg_4_1 == true then
                local var_4_10
                local var_4_11

                var_4_11, var_4_9 = sampGetPlayerIdByCharHandle(PLAYER_PED)
            else
                var_4_9 = tonumber(arg_4_1)
            end

            var_4_7(var_4_9, var_4_6)
        end
    end

    local function var_4_12()
        local var_5_0 = raknetNewBitStream()

        raknetBitStreamWriteInt8(var_5_0, var_4_3[2])
        raknetBitStreamWriteBuffer(var_5_0, var_4_6, var_4_0.sizeof(var_4_5))
        raknetSendBitStreamEx(var_5_0, var_4_1.HIGH_PRIORITY, var_4_1.UNRELIABLE_SEQUENCED, 1)
        raknetDeleteBitStream(var_5_0)
    end

    local var_4_13 = {
        __index = function(arg_6_0, arg_6_1)
            return var_4_5[arg_6_1]
        end,
        __newindex = function(arg_7_0, arg_7_1, arg_7_2)
            var_4_5[arg_7_1] = arg_7_2
        end
    }

    return setmetatable({
        send = var_4_12
    }, var_4_13)
end

function getMoveSpeed(heading, speed) return {x = math.sin(-math.rad(heading)) * speed, y = math.cos(-math.rad(heading)) * speed, z = 0} end
function getFullSpeed(speed, ping, min_ping) 
    local fps = memory.getfloat(0xB7CB50, true); local result = (speed / (fps / 60)) 
    if ping == 1 then local p = sampGetPlayerPing(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))); if min_ping < p then result = (result / (min_ping / p)) end end 
    return result 
end 

-- === ИСХОДЯЩАЯ СИНХРА (САМОПРОВЕРКА И АИРБРЕЙК) ===
function sampev.onSendPlayerSync(data)
    local modified = false
    local current_time = os.clock()

    -- Самопроверка на читерское оружие
    if st.cfg_warn_cheat_weap[0] then
        local w = data.weapon
        if cheat_weapons and cheat_weapons[w] then
            if not weap_warn_time[-1] or (current_time - weap_warn_time[-1]) > 15.0 then
                weap_warn_time[-1] = current_time
                sampAddChatMessage(u8:decode(string.format("{FFFF00}[GibsonHelper]{FFFFFF} Вы сами держите читерское оружие (%s)!", cheat_weapons[w])), -1)
            end
        end
    end

    -- Самопроверка на рванку с ног
    if st.cfg_warn_rvanka[0] then
        local speed = math.sqrt(data.moveSpeed.x^2 + data.moveSpeed.y^2 + data.moveSpeed.z^2)
        if speed > 2.5 or data.moveSpeed.z > 1.5 then
            if not rvanka_warn_time[-1] or (current_time - rvanka_warn_time[-1]) > 10.0 then
                rvanka_warn_time[-1] = current_time
                sampAddChatMessage(u8:decode("{FFFF00}[GibsonHelper]{FFFFFF} Вы сами летите с подозрительной скоростью (с ног)!"), -1)
            end
        end
    end

    if st.ab_active and st.cfg_ab_state[0] then
        local fuck = getMoveSpeed(getCharHeading(PLAYER_PED), st.cfg_ab_sync_player[0])
        data.moveSpeed = {fuck.x, fuck.y, data.moveSpeed.z}
        modified = true
    end

    if st.cfg_adm_invis[0] and st.invis_active then
        local spec_sync = samp_create_sync_data("spectator")
        spec_sync.position = data.position
        spec_sync.send()
        return false 
    end

    if modified then return data end
end

function sampev.onSendVehicleSync(data)
    -- Самопроверка на рванку в машине
    if st.cfg_warn_rvanka[0] then
        local speed = math.sqrt(data.moveSpeed.x^2 + data.moveSpeed.y^2 + data.moveSpeed.z^2)
        if speed > 2.5 or data.moveSpeed.z > 1.5 then
            local current_time = os.clock()
            if not rvanka_warn_time[-1] or (current_time - rvanka_warn_time[-1]) > 10.0 then
                rvanka_warn_time[-1] = current_time
                sampAddChatMessage(u8:decode("{FFFF00}[GibsonHelper]{FFFFFF} Вы сами летите с подозрительной скоростью (в машине)!"), -1)
            end
        end
    end

    if not st.ab_active or not st.cfg_ab_state[0] then return end
    local fuck = getMoveSpeed(getCharHeading(PLAYER_PED), st.cfg_ab_sync_vehicle[0])
    data.moveSpeed = {fuck.x, fuck.y, data.moveSpeed.z}; return data
end
function sampev.onSendUnoccupiedSync(data)
    if not st.ab_active or not st.cfg_ab_state[0] then return end
    local fuck = getMoveSpeed(getCharHeading(PLAYER_PED), st.cfg_ab_sync_passenger[0])
    data.moveSpeed = {fuck.x, fuck.y, data.moveSpeed.z}; return data
end
function sampev.onSendPassengerSync(data)
    if not st.ab_active or not st.cfg_ab_state[0] then return end
    data.position = {getCharCoordinates(PLAYER_PED)}; return data
end

addEventHandler('onWindowMessage', function(msg, wparam, lparam)
    if st.cfg_ab_state[0] and (msg == 0x100 or msg == 0x101) then 
        if lparam == 3538945 and not sampIsChatInputActive() and not sampIsDialogActive() and not sampIsCursorActive() then 
            st.airBrkCoords = {getCharCoordinates(PLAYER_PED)} 
            if not isCharInAnyCar(PLAYER_PED) then st.airBrkCoords[3] = st.airBrkCoords[3] - 1 end
            st.ab_active = not st.ab_active
            printStringNow(st.ab_active and '~S~Air~P~Brake ~B~Activated' or '~S~Air~P~Brake ~B~De-Activated', 2000)
        end
    end
end)

function toggleCwCursor(toggle)
    if toggle then 
        sampToggleCursor(true)
        sampSetCursorMode(2)
    else
        sampToggleCursor(false)
        sampSetCursorMode(0)
    end
    st.cw_cursorEnabled = toggle
end
function createPointMarker(x, y, z) st.cw_pointMarker = createUser3dMarker(x, y, z + 0.3, 4) end
function removePointMarker() if st.cw_pointMarker then removeUser3dMarker(st.cw_pointMarker); st.cw_pointMarker = nil end end

function displayVehicleName(x, y, gxt)
    x, y = convertWindowScreenCoordsToGameScreenCoords(x, y)
    useRenderCommands(true); setTextWrapx(640.0); setTextProportional(true); setTextJustify(false); setTextScale(0.33, 0.8)
    setTextDropshadow(0, 0, 0, 0, 0); setTextColour(255, 255, 255, 230); setTextEdge(1, 0, 0, 0, 100); setTextFont(1); displayText(x, y, gxt)
end

function setEntityCoordinates(entityPtr, x, y, z)
    if entityPtr ~= 0 then
        local matrixPtr = readMemory(entityPtr + 0x14, 4, false)
        if matrixPtr ~= 0 then
            local posPtr = matrixPtr + 0x30
            writeMemory(posPtr + 0, 4, representFloatAsInt(x), false)
            writeMemory(posPtr + 4, 4, representFloatAsInt(y), false)
            writeMemory(posPtr + 8, 4, representFloatAsInt(z), false)
        end
    end
end

function setCharCoordinatesDontResetAnim(char, x, y, z)
    if doesCharExist(char) then local ptr = getCharPointer(char); setEntityCoordinates(ptr, x, y, z) end
end

function teleportPlayer(x, y, z)
    if isCharInAnyCar(PLAYER_PED) then setCharCoordinates(PLAYER_PED, x, y, z) end
    setCharCoordinatesDontResetAnim(PLAYER_PED, x, y, z)
end

function getCarFreeSeat(car)
    if doesCharExist(getDriverOfCar(car)) then
        local maxPassengers = getMaximumNumberOfPassengers(car)
        for i = 0, maxPassengers do if isCarPassengerSeatFree(car, i) then return i + 1 end end
        return nil
    else return 0 end
end

function jumpIntoCar(car)
    local seat = getCarFreeSeat(car)
    if not seat then return false end
    if seat == 0 then warpCharIntoCar(PLAYER_PED, car) else warpCharIntoCarAsPassenger(PLAYER_PED, car, seat - 1) end
    restoreCameraJumpcut(); return true
end

function readFloatArray(ptr, idx) return representIntAsFloat(readMemory(ptr + idx * 4, 4, false)) end
function writeFloatArray(ptr, idx, value) writeMemory(ptr + idx * 4, 4, representFloatAsInt(value), false) end

function getVehicleRotationMatrix(car)
    local entityPtr = getCarPointer(car)
    if entityPtr ~= 0 then
        local mat = readMemory(entityPtr + 0x14, 4, false)
        if mat ~= 0 then return readFloatArray(mat, 0), readFloatArray(mat, 1), readFloatArray(mat, 2), readFloatArray(mat, 4), readFloatArray(mat, 5), readFloatArray(mat, 6), readFloatArray(mat, 8), readFloatArray(mat, 9), readFloatArray(mat, 10) end
    end
end

function setVehicleRotationMatrix(car, rx, ry, rz, fx, fy, fz, ux, uy, uz)
    local entityPtr = getCarPointer(car)
    if entityPtr ~= 0 then
        local mat = readMemory(entityPtr + 0x14, 4, false)
        if mat ~= 0 then writeFloatArray(mat, 0, rx); writeFloatArray(mat, 1, ry); writeFloatArray(mat, 2, rz); writeFloatArray(mat, 4, fx); writeFloatArray(mat, 5, fy); writeFloatArray(mat, 6, fz); writeFloatArray(mat, 8, ux); writeFloatArray(mat, 9, uy); writeFloatArray(mat, 10, uz) end
    end
end

function rotateCarAroundUpAxis(car, vec)
    local mat = Matrix3X3(getVehicleRotationMatrix(car)); local rotAxis = Vector3D(mat.up:get()); vec:normalize(); rotAxis:normalize()
    local theta = math.acos(rotAxis:dotProduct(vec))
    if theta ~= 0 then rotAxis:crossProduct(vec); rotAxis:normalize(); rotAxis:zeroNearZero(); mat = mat:rotate(rotAxis, -theta) end
    setVehicleRotationMatrix(car, mat:get())
end

local player_vehicle_ptr = samem.cast('CVehicle **', samem.player_vehicle)
local sh_timer = { prev_time = 0 }

function sh_timer:process(timestep)
    local curr_time = os.clock()
    if (curr_time - self.prev_time) >= timestep then
        self.prev_time = curr_time
        return true
    end
    return false
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    CheckForUpdates()
    
    initRules()

    cw_font = renderCreateFont("Arial", 11, 5)
    cw_font2 = renderCreateFont("Arial", 8, 6)
    tracer_font = renderCreateFont("Arial", 10, 1)

    sampRegisterChatCommand("amenu", function() st.renderWindow[0] = not st.renderWindow[0] end)

    while true do
        wait(0)

        if st.cfg_adm_invis[0] and st.invis_active then
            local sw, sh = getScreenResolution()
            renderFontDrawText(cw_font, "Invisible: ON", sw / 2 - 50, sh - 150, 0xFF00FF00)
        end

        if st.cfg_bt_active[0] then
            local current_time = os.clock()
            for i = #st.tracers, 1, -1 do
                local tr = st.tracers[i]
                if current_time > tr.time then
                    table.remove(st.tracers, i)
                else
                    local res1, wX, wY, wZ = convert3DCoordsToScreenEx(tr.ox, tr.oy, tr.oz, true, true)
                    local res2, pX, pY, pZ = convert3DCoordsToScreenEx(tr.tx, tr.ty, tr.tz, true, true)
                    
                    if res1 and res2 then
                        local xResolution = memory.getuint32(0x00C17044)
                        if wZ < 1 then wX = xResolution - wX end
                        if pZ < 1 then pZ = xResolution - pZ end 
                        
                        renderDrawLine(wX, wY, pX, pY, st.cfg_bt_thickness[0], tr.color)
                        
                        if st.cfg_bt_show_id[0] and tr.id ~= -1 then
                            renderFontDrawText(tracer_font, tostring(tr.id), wX + 5, wY, 0xFFFFFFFF, false)
                        end
                    end
                end
            end
        end

        if st.cfg_ab_state[0] and st.ab_active then
            local speed = 0
            if isCharInAnyCar(PLAYER_PED) then 
                setCarHeading(getCarCharIsUsing(PLAYER_PED), getHeadingFromVector2d(select(1, getActiveCameraPointAt()) - select(1, getActiveCameraCoordinates()), select(2, getActiveCameraPointAt()) - select(2, getActiveCameraCoordinates()))) 
                if getDriverOfCar(getCarCharIsUsing(PLAYER_PED)) == -1 then speed = getFullSpeed(st.cfg_ab_speed_passenger[0], 0, 0) else speed = getFullSpeed(st.cfg_ab_speed_vehicle[0], 0, 0) end 
            else 
                speed = getFullSpeed(st.cfg_ab_speed_player[0], 0, 0) 
                setCharHeading(PLAYER_PED, getHeadingFromVector2d(select(1, getActiveCameraPointAt()) - select(1, getActiveCameraCoordinates()), select(2, getActiveCameraPointAt()) - select(2, getActiveCameraCoordinates()))) 
            end

            if not sampIsCursorActive() then
                if isKeyDown(vkeys.VK_SPACE) then st.airBrkCoords[3] = st.airBrkCoords[3] + speed / 2 
                elseif isKeyDown(vkeys.VK_LSHIFT) and st.airBrkCoords[3] > -95.0 then st.airBrkCoords[3] = st.airBrkCoords[3] - speed / 2 end

                if isKeyDown(vkeys.VK_W) then st.airBrkCoords[1] = st.airBrkCoords[1] + speed * math.sin(-math.rad(getCharHeading(PLAYER_PED))); st.airBrkCoords[2] = st.airBrkCoords[2] + speed * math.cos(-math.rad(getCharHeading(PLAYER_PED))) 
                elseif isKeyDown(vkeys.VK_S) then st.airBrkCoords[1] = st.airBrkCoords[1] - speed * math.sin(-math.rad(getCharHeading(PLAYER_PED))); st.airBrkCoords[2] = st.airBrkCoords[2] - speed * math.cos(-math.rad(getCharHeading(PLAYER_PED))) end
                
                if isKeyDown(vkeys.VK_A) then st.airBrkCoords[1] = st.airBrkCoords[1] - speed * math.sin(-math.rad(getCharHeading(PLAYER_PED) - 90)); st.airBrkCoords[2] = st.airBrkCoords[2] - speed * math.cos(-math.rad(getCharHeading(PLAYER_PED) - 90)) 
                elseif isKeyDown(vkeys.VK_D) then st.airBrkCoords[1] = st.airBrkCoords[1] + speed * math.sin(-math.rad(getCharHeading(PLAYER_PED) - 90)); st.airBrkCoords[2] = st.airBrkCoords[2] + speed * math.cos(-math.rad(getCharHeading(PLAYER_PED) - 90)) end
            end

            setCharCoordinates(PLAYER_PED, st.airBrkCoords[1], st.airBrkCoords[2], st.airBrkCoords[3])
        end

        if st.cfg_adm_clickwarp[0] then
            if wasKeyPressed(vkeys.VK_MBUTTON) and not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive() then
                st.cw_cursorEnabled = not st.cw_cursorEnabled
                toggleCwCursor(st.cw_cursorEnabled)
            end

            if isPauseMenuActive() and st.cw_cursorEnabled then
                toggleCwCursor(false)
            end

            if st.cw_cursorEnabled then
                local sx, sy = getCursorPos()
                local sw, sh = getScreenResolution()
                
                if sx >= 0 and sy >= 0 and sx < sw and sy < sh then
                    local posX, posY, posZ = convertScreenCoordsToWorld3D(sx, sy, 700.0)
                    local camX, camY, camZ = getActiveCameraCoordinates()
                    local result, colpoint = processLineOfSight(camX, camY, camZ, posX, posY, posZ, true, true, false, true, false, false, false)

                    if result and colpoint.entity ~= 0 then
                        local normal = colpoint.normal
                        local pos = Vector3D(colpoint.pos[1], colpoint.pos[2], colpoint.pos[3]) - (Vector3D(normal[1], normal[2], normal[3]) * 0.1)
                        local zOffset = 300
                        if normal[3] >= 0.5 then zOffset = 1 end

                        local result2, colpoint2 = processLineOfSight(pos.x, pos.y, pos.z + zOffset, pos.x, pos.y, pos.z - 0.3, true, true, false, true, false, false, false)
                        if result2 then
                            pos = Vector3D(colpoint2.pos[1], colpoint2.pos[2], colpoint2.pos[3] + 1)
                            local curX, curY, curZ = getCharCoordinates(PLAYER_PED)
                            local dist = getDistanceBetweenCoords3d(curX, curY, curZ, pos.x, pos.y, pos.z)
                            local hoffs = renderGetFontDrawHeight(cw_font)

                            sy = sy - 2; sx = sx - 2
                            renderFontDrawText(cw_font, string.format("%0.2fm", dist), sx, sy - hoffs, 0xEEEEEEEE)

                            local tpIntoCar = nil
                            if colpoint.entityType == 2 then
                                local car = getVehiclePointerHandle(colpoint.entity)
                                if doesVehicleExist(car) and (not isCharInAnyCar(PLAYER_PED) or storeCarCharIsInNoSave(PLAYER_PED) ~= car) then
                                    displayVehicleName(sx, sy - hoffs * 2, getNameOfVehicleModel(getCarModel(car)))
                                    local color = 0xAAFFFFFF
                                    if isKeyDown(vkeys.VK_RBUTTON) then tpIntoCar = car; color = 0xFFFFFFFF end
                                    renderFontDrawText(cw_font2, u8:decode("Удерживайте ПКМ + ЛКМ для посадки"), sx, sy - hoffs * 3, color)
                                end
                            end

                            createPointMarker(pos.x, pos.y, pos.z)

                            if isKeyDown(vkeys.VK_LBUTTON) then
                                if tpIntoCar then
                                    if not jumpIntoCar(tpIntoCar) then teleportPlayer(pos.x, pos.y, pos.z) end
                                else
                                    if isCharInAnyCar(PLAYER_PED) then
                                        local norm = Vector3D(colpoint.normal[1], colpoint.normal[2], 0)
                                        local norm2 = Vector3D(colpoint2.normal[1], colpoint2.normal[2], colpoint2.normal[3])
                                        rotateCarAroundUpAxis(storeCarCharIsInNoSave(PLAYER_PED), norm2)
                                        pos = pos - norm * 1.8; pos.z = pos.z - 0.8
                                    end
                                    teleportPlayer(pos.x, pos.y, pos.z)
                                end
                                removePointMarker()
                                while isKeyDown(vkeys.VK_LBUTTON) do wait(0) end
                                toggleCwCursor(false)
                            end
                        else
                            removePointMarker()
                        end
                    else
                        removePointMarker()
                    end
                else
                    removePointMarker()
                end
            else
                removePointMarker()
            end
        else
            if st.cw_cursorEnabled then toggleCwCursor(false) end
            removePointMarker()
        end

        if not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive() then
            if st.hk_menu[0]   ~= 0 and wasKeyPressed(st.hk_menu[0])   then st.renderWindow[0] = not st.renderWindow[0] end
            if st.hk_report[0] ~= 0 and wasKeyPressed(st.hk_report[0]) then st.reportWindow[0] = not st.reportWindow[0] end
            
            if st.hk_rules[0] ~= 0 and wasKeyPressed(st.hk_rules[0]) then
                st.renderWindow[0] = true
                st.activeTab[0] = 8
            end
            
            if st.hk_invis[0] ~= 0 and wasKeyPressed(st.hk_invis[0]) then
                if st.cfg_adm_invis[0] then 
                    st.invis_active = not st.invis_active 
                    sampAddChatMessage(u8:decode("[GibsonHelper] Невидимка " .. (st.invis_active and "{00FF00}Включена" or "{FF0000}Выключена")), -1)
                end
            end

            if st.cfg_adm_gm_car[0] then
                if isCharOnFoot(PLAYER_PED) then
                    st.last_gm_car = 0
                elseif isCharInAnyPlane(PLAYER_PED) then 
                    local veh = getCarCharIsUsing(PLAYER_PED)
                    st.last_gm_car = veh
                    setCarProofs(veh, true, true, true, true, true)
                elseif isCharInAnyCar(PLAYER_PED) then
                    local veh = getCarCharIsUsing(PLAYER_PED)
                    st.last_gm_car = veh
                    setCarProofs(veh, true, true, true, false, false)
                    
                    if isCarTireBurst(veh, 0) or isCarTireBurst(veh, 1) or isCarTireBurst(veh, 2) or isCarTireBurst(veh, 3) then
                        fixCarTire(veh, 0); fixCarTire(veh, 1); fixCarTire(veh, 2); fixCarTire(veh, 3)
                    end
                    if isKeyDown(vkeys.VK_DELETE) then
                        setVehicleQuaternion(veh, 0, 0, 0, 0)
                    end
                    if getCarHealth(veh) < 900 then 
                        setCarHealth(veh, 900)
                    end
                end
            else
                if st.last_gm_car ~= 0 and doesVehicleExist(st.last_gm_car) then
                    setCarProofs(st.last_gm_car, false, false, false, false, false)
                    st.last_gm_car = 0
                end
            end

            if st.cfg_adm_speedhack[0] then
                local veh = player_vehicle_ptr[0]
                if veh ~= samem.nullptr then
                    local key_name = ffi.string(st.sh_key)
                    local kid = vkeys.name_to_id(key_name, false)
                    if kid and isKeyDown(kid) then
                        if sh_timer:process(st.sh_timestep[0]) then
                            if veh.nVehicleClass == 6 then
                                local train = samem.cast('CTrain *', veh)
                                while train ~= samem.nullptr do
                                    local new_speed = train.fTrainSpeed * st.sh_mult[0]
                                    if st.sh_safe_train[0] then
                                        if new_speed >= 0.99 then
                                            new_speed = 0.9
                                        end
                                    end
                                    if new_speed <= st.sh_limit[0] then
                                        train.fTrainSpeed = new_speed
                                    end
                                    train = train.pNextCarriage
                                end
                            else
                                while veh ~= samem.nullptr do
                                    local new_speed = veh.vMoveSpeed * st.sh_mult[0]
                                    if new_speed:magnitude() <= st.sh_limit[0] then
                                        veh.vMoveSpeed = new_speed
                                    end
                                    veh = veh.pTrailer
                                end
                            end
                        end
                    end
                end
            end
        end

        -- === ЛОГИКА NOBIKE ===
        if st.nb_active[0] then
            if isCharOnAnyBike(PLAYER_PED) then
                setCharCanBeKnockedOffBike(PLAYER_PED, true) 
            end
        else
            if isCharOnAnyBike(PLAYER_PED) then
                setCharCanBeKnockedOffBike(PLAYER_PED, false) 
            end
        end

     -- === ЛОГИКА WALLHACK ===
        if st.cfg_wh_state[0] then
            -- Читаем режим из меню (0 = Всё, 1 = Только кости, 2 = Только ники)
            local wh_mode = st.cfg_wh_mode[0]

            if not isPauseMenuActive() and not isKeyDown(vkeys.VK_F8) then
                if (wh_mode == 0 or wh_mode == 2) and not nameTag then
                    nameTagOn()
                elseif wh_mode == 1 and nameTag then
                    nameTagOff()
                end

                for i = 0, sampGetMaxPlayerId() do
                    if sampIsPlayerConnected(i) then
                        local result, cped = sampGetCharHandleBySampPlayerId(i)
                        
                        if result and doesCharExist(cped) then
                            -- Вычисляем дистанцию до отрисовки
                            local px, py, pz = getCharCoordinates(PLAYER_PED)
                            local cx, cy, cz = getCharCoordinates(cped)
                            local dist = getDistanceBetweenCoords3d(cx, cy, cz, px, py, pz)
                            
                            -- Если игрок в радиусе нашей дистанции из настроек
                            if dist <= st.cfg_wh_distance[0] then
                                -- Получаем цвет игрока и делаем его непрозрачным (255)
                                local color = sampGetPlayerColor(i) or 0xFFFFFFFF
                                local aa, rr, gg, bb = explode_argb(color)
                                local drawColor = join_argb(255, rr, gg, bb)

                                -- 1. РЕНДЕР НИКОВ И ID
                                if wh_mode == 0 or wh_mode == 2 then
                                    -- Берем координаты головы (кость 8)
                                    local hx, hy, hz = getBodyPartCoordinates(8, cped)
                                    local is_head_found = true
                                    
                                    if hx == 0 and hy == 0 then
                                        hx, hy, hz = cx, cy, cz
                                        is_head_found = false
                                    end
                                    
                                    -- Формула динамического отступа с привязкой к ползунку из меню
                                    local dynamic_z = st.cfg_wh_name_height[0] + (dist * 0.035)
                                    
                                    if is_head_found then
                                        hz = hz + dynamic_z
                                    else
                                        hz = hz + dynamic_z + 0.8
                                    end
                                    
                                    -- ПРОВЕРКА КАМЕРЫ ДЛЯ ТЕКСТА
                                    if isPointOnScreen(hx, hy, hz, 0.0) then
                                        local val1, val2, val3 = convert3DCoordsToScreen(hx, hy, hz)
                                        local res_text, sx, sy
                                        
                                        if type(val1) == "boolean" then
                                            res_text, sx, sy = val1, val2, val3
                                        else
                                            res_text, sx, sy = true, val1, val2
                                        end
                                        
                                        if res_text and sx ~= nil and sy ~= nil then
                                            local name = sampGetPlayerNickname(i) or "Unknown"
                                            local text = string.format("%s [%d] | %.0fm", name, i, dist)
                                            
                                            local tLen = renderGetFontDrawTextLength(cw_font, text)
                                            if type(tLen) ~= "number" then tLen = 50 end
                                            local drawX = sx - (tLen / 2)
                                            
                                            renderFontDrawText(cw_font, text, drawX, sy, drawColor)
                                        end
                                    end
                                end

                                -- 2. РЕНДЕР КОСТЕЙ
                                if wh_mode == 0 or wh_mode == 1 then
                                    local function getScreenCoords(x, y, z)
                                        -- ПРОВЕРКА КАМЕРЫ ДЛЯ КОСТЕЙ
                                        if not isPointOnScreen(x, y, z, 0.0) then return false, 0, 0 end
                                        
                                        local v1, v2, v3 = convert3DCoordsToScreen(x, y, z)
                                        if type(v1) == "boolean" then return v1, v2, v3 end
                                        return true, v1, v2
                                    end

                                    local t_bones = {3, 4, 5, 51, 52, 41, 42, 31, 32, 33, 21, 22, 23, 2}
                                    local pos1_saved_x, pos1_saved_y
                                    local b_thick = st.cfg_wh_bone_thick[0] -- Берем толщину из ползунка
                                    
                                    for v = 1, #t_bones do
                                        local p1x, p1y, p1z = getBodyPartCoordinates(t_bones[v], cped)
                                        local p2x, p2y, p2z = getBodyPartCoordinates(t_bones[v] + 1, cped)
                                        
                                        if p1x ~= 0 and p2x ~= 0 then
                                            local res1, sx1, sy1 = getScreenCoords(p1x, p1y, p1z)
                                            local res2, sx2, sy2 = getScreenCoords(p2x, p2y, p2z)
                                            
                                            if res1 and res2 and sx1 and sy1 and sx2 and sy2 then 
                                                renderDrawLine(sx1, sy1, sx2, sy2, b_thick, drawColor) 
                                                pos1_saved_x, pos1_saved_y = sx1, sy1
                                            end
                                        end
                                    end
                                    
                                    for v = 4, 5 do
                                        local p2x, p2y, p2z = getBodyPartCoordinates(v * 10 + 1, cped)
                                        if p2x ~= 0 then
                                            local res2, sx2, sy2 = getScreenCoords(p2x, p2y, p2z)
                                            if res2 and sx2 and sy2 and pos1_saved_x and pos1_saved_y then
                                                renderDrawLine(pos1_saved_x, pos1_saved_y, sx2, sy2, b_thick, drawColor)
                                            end
                                        end
                                    end
                                    
                                    local t_extra = {53, 43, 24, 34, 6}
                                    for v = 1, #t_extra do
                                        local p1x, p1y, p1z = getBodyPartCoordinates(t_extra[v], cped)
                                        if p1x ~= 0 then
                                            getScreenCoords(p1x, p1y, p1z) 
                                        end
                                    end
                                end
                            end -- конец if dist
                        end
                    end
                end
            else
                if nameTag then nameTagOff() end
            end
        else
            if nameTag then nameTagOff() end
        end
    end
end