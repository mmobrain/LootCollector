

local L = LootCollector
local Constants = L:NewModule("Constants")

Constants.PROTO_V = 5

Constants.MIN_COMPATIBLE_VERSION = "0.5.90"

Constants.OP = {
    DISC = "DISC",
    CONF = "CONF",
    ACK  = "ACK",
}

Constants.ACT = {
    DET = "DET", 
    VER = "VER", 
    SPM = "SPM", 
    DUP = "DUP", 
}

Constants.STATUS = {
    UNCONFIRMED = "UNCONFIRMED",
    CONFIRMED   = "CONFIRMED",
    FADING      = "FADING",
    STALE       = "STALE",
}

Constants.COORD_PRECISION     = 4       
Constants.MAX_CHAT_BYTES      = 240     
Constants.DEFLATE_LEVEL       = 9       

Constants.REINFORCE_TAKEOVER_GRACE_SECONDS = 10800
Constants.SEEN_TTL_SECONDS    = 1800
Constants.COOLDOWN_TTL        = 300     
Constants.CHAT_MIN_INTERVAL   = 3.50    

Constants.ACK_HOLD_THRESHOLD  = 21      
Constants.ACK_SENDER_TTL      = 900     

Constants.ADDON_PREFIX_DEFAULT = "BBLC25AM"
Constants.CHANNEL_NAME_DEFAULT = "BBLC25C"

Constants.DISCOVERY_TYPE = {
    UNKNOWN = 0,
    WORLDFORGED = 1,
    MYSTIC_SCROLL = 2,
    BLACKMARKET = 3,
}

Constants.ALLOWED_DISCOVERY_TYPES = {
    [Constants.DISCOVERY_TYPE.WORLDFORGED] = true,
	[Constants.DISCOVERY_TYPE.MYSTIC_SCROLL] = true,	
}

Constants.AcceptedLootSrcWF = {
    world_loot = 0,
}

Constants.AcceptedLootSrcMS = {
    world_loot = 0,
    npc_gossip = 1,
    emote_event = 2,
    direct = 3,
}

Constants.ITEM_TYPE_TO_ID = {
    
    ["Armor"] = 1, ["Rüstung"] = 1, ["Armure"] = 1, ["방어구"] = 1, ["Armadura"] = 1, ["Доспехи"] = 1, ["护甲"] = 1,
    
    ["Container"] = 2, ["Behälter"] = 2, ["Conteneur"] = 2, ["가방"] = 2, ["Contenedor"] = 2, ["Сумки"] = 2, ["容器"] = 2,
    
    ["Consumable"] = 3, ["Verbrauchbar"] = 3, ["Consommable"] = 3, ["소비 용품"] = 3, ["Consumible"] = 3, ["Расходуемые"] = 3, ["消耗品"] = 3,
    
    ["Weapon"] = 4, ["Waffe"] = 4, ["Arme"] = 4, ["무기"] = 4, ["Arma"] = 4, ["Оружие"] = 4, ["武器"] = 4,
    
    ["Gem"] = 5, ["Edelstein"] = 5, ["Gemme"] = 5, ["보석"] = 5, ["Gema"] = 5, ["Самоцветы"] = 5, ["宝石"] = 5,
    
    ["Trade Goods"] = 6, ["Handwerkswaren"] = 6, ["Artisanat"] = 6, ["직업 용품"] = 6, ["Objeto comerciable"] = 6, ["Хозяйственные товары"] = 6, ["商品"] = 6,
    
    ["Reagent"] = 7, ["Reagenz"] = 7, ["Réactif"] = 7, ["재료"] = 7, ["Reactivo"] = 7, ["Реагенты"] = 7,
    
    ["Recipe"] = 8, ["Rezept"] = 8, ["Recette"] = 8, ["제조법"] = 8, ["Receta"] = 8, ["Рецепты"] = 8, ["配方"] = 8,
    
    ["Projectile"] = 9, ["Projektil"] = 9, ["투사체"] = 9, ["Proyectil"] = 9, ["Боеприпасы"] = 9, ["弹药"] = 9,
    
    ["Quest"] = 10, ["퀘스트"] = 10, ["Misión"] = 10, ["Задания"] = 10, ["任务"] = 10, ["Quête"] = 10,
    
    ["Key"] = 11, ["Schlüssel"] = 11, ["Clé"] = 11, ["열쇠"] = 11, ["Llave"] = 11, ["Ключ"] = 11, ["钥匙"] = 11,
    
    ["Miscellaneous"] = 12, ["Verschiedenes"] = 12, ["Divers"] = 12, ["기타"] = 12, ["Misceláneas"] = 12, ["Разное"] = 12, ["其他"] = 12, ["Miscelánea"] = 12,
    
    ["Glyph"] = 13, ["Glyphe"] = 13, ["문양"] = 13, ["Glifo"] = 13, ["Символ"] = 13, ["雕文"] = 13,
}

Constants.ITEM_SUBTYPE_TO_ID = {
    
    ["Cloth"] = 1, ["Stoff"] = 1, ["Tissu"] = 1, ["천"] = 1, ["Tela"] = 1, ["Ткань"] = 1, ["布甲"] = 1,
    ["Leather"] = 2, ["Leder"] = 2, ["Cuir"] = 2, ["가죽"] = 2, ["Cuero"] = 2, ["Кожа"] = 2, ["皮甲"] = 2,
    ["Mail"] = 3, ["Schwere Rüstung"] = 3, ["Mailles"] = 3, ["사슬"] = 3, ["Mallas"] = 3, ["Кольчуга"] = 3, ["锁甲"] = 3,
    ["Plate"] = 4, ["Platte"] = 4, ["Plaques"] = 4, ["판금"] = 4, ["Placas"] = 4, ["Латы"] = 4, ["板甲"] = 4,
    ["Shields"] = 5, ["Schilde"] = 5, ["Boucliers"] = 5, ["방패"] = 5, ["Escudos"] = 5, ["Щиты"] = 5, ["盾牌"] = 5,
    ["Librams"] = 6, ["Buchbände"] = 6, ["Librams"] = 6, ["성서"] = 6, ["Tratados"] = 6, ["Манускрипты"] = 6, ["圣契"] = 6,
    ["Idols"] = 7, ["Götzen"] = 7, ["Idoles"] = 7, ["우상"] = 7, ["Ídolos"] = 7, ["Идолы"] = 7, ["神像"] = 7, ["Ã dolos"] = 7, ["塑像"] = 7,
    ["Totems"] = 8, ["Totems"] = 8, ["토템"] = 8, ["Tótems"] = 8, ["Тотемы"] = 8, ["图腾"] = 8,
    ["Sigils"] = 9, ["Siegel"] = 9, ["Glyphes"] = 9, ["인장"] = 9, ["Sigilos"] = 9, ["Печати"] = 9, ["魔印"] = 9, ["符印"] = 9,
    
    ["Bag"] = 10, ["Sac"] = 10,
    ["Soul Bag"] = 11, ["Seelentasche"] = 11, ["Sac d'âme"] = 11, ["영혼의 가방"] = 11, ["Bolsa de almas"] = 11, ["Сумка душ"] = 11, ["灵魂袋"] = 11, ["Bolsa de Almas"] = 11, ["靈魂裂片包"] = 11,
    ["Herb Bag"] = 12, ["Kräutertasche"] = 12, ["Sac d'herbes"] = 12, ["약초 가방"] = 12, ["Bolsa de hierbas"] = 12, ["Сумка травника"] = 12, ["草药袋"] = 12,
    ["Enchanting Bag"] = 13, ["Verzauberertasche"] = 13, ["Sac d'enchanteur"] = 13, ["마법부여 가방"] = 13, ["Bolsa de encantamiento"] = 13, ["Сумка зачаровывателя"] = 13, ["附魔材料袋"] = 13, ["附魔包"] = 13,
    ["Engineering Bag"] = 14, ["Ingenieurstasche"] = 14, ["Sac d'ingénieur"] = 14, ["기계공학 가방"] = 14, ["Bolsa de ingeniería"] = 14, ["Сумка инженера"] = 14, ["工程学材料袋"] = 14, ["工程包"] = 14,
    ["Gem Bag"] = 15, ["Edelsteintasche"] = 15, ["Sac de gemmes"] = 15, ["보석 가방"] = 15, ["Bolsa de gemas"] = 15, ["Сумка ювелира"] = 15, ["宝石袋"] = 15, ["Bolsa de Gemas"] = 15, ["寶石包"] = 15,
    ["Mining Bag"] = 16, ["Bergbautasche"] = 16, ["Sac de mineur"] = 16, ["채광 가방"] = 16, ["Bolsa de minería"] = 16, ["Сумка шахтера"] = 16, ["矿石袋"] = 16, ["Bolsa de Minería"] = 16, ["礦石包"] = 16,
    ["Leatherworking Bag"] = 17, ["Lederertasche"] = 17, ["Sac de travail du cuir"] = 17, ["가죽세공 가방"] = 17, ["Bolsa de peletería"] = 17, ["Сумка кожевника"] = 17, ["制皮材料袋"] = 17, ["Bolsa de Peletería"] = 17, ["製皮包"] = 17,
    ["Inscription Bag"] = 18, ["Schreibertasche"] = 18, ["Sac de calligraphie"] = 18, ["주문각인 가방"] = 18, ["Bolsa de inscripción"] = 18, ["Сумка начертателя"] = 18, ["铭文包"] = 18,
    ["Quiver"] = 19, ["Köcher"] = 19, ["Carquois"] = 19, ["화살통"] = 19, ["Carcaj"] = 19, ["Амуниция"] = 19, ["箭袋"] = 19,
    ["Ammo Pouch"] = 20, ["Munitionsbeutel"] = 20, ["Giberne"] = 20, ["탄환 주머니"] = 20, ["Bolsa de munición"] = 20, ["Подсумок"] = 20, ["弹药袋"] = 20, ["Bolsa de Munición"] = 20, ["彈藥包"] = 20,
    
    ["Food & Drink"] = 21, ["Speis & Trank"] = 21, ["Nourriture & boissons"] = 21, ["음식과 음료"] = 21, ["Comida y bebida"] = 21, ["Еда и напитки"] = 21, ["食物和饮料"] = 21,
    ["Potion"] = 22, ["Trank"] = 22, ["물약"] = 22, ["Poción"] = 22, ["Зелье"] = 22, ["药水"] = 22, ["藥水"] = 22,
    ["Elixir"] = 23, ["Elixier"] = 23, ["Élixir"] = 23, ["영약"] = 23, ["Эликсир"] = 23, ["药剂"] = 23, ["藥劑"] = 23,
    ["Flask"] = 24, ["Fläschchen"] = 24, ["Flacon"] = 24, ["비약"] = 24, ["Frasco"] = 24, ["Фляга"] = 24, ["合剂"] = 24, ["精煉藥劑"] = 24,
    ["Bandage"] = 25, ["Verband"] = 25, ["붕대"] = 25, ["Venda"] = 25, ["Бинты"] = 25, ["绷带"] = 25, ["繃帶"] = 25,
    ["Item Enhancement"] = 26, ["Gegenstandsverbesserung"] = 26, ["Amélioration d'objet"] = 26, ["아이템 강화"] = 26, ["Mejora de Objeto"] = 26, ["Улучшение"] = 26, ["物品强化"] = 26,
    ["Scroll"] = 27, ["Rolle"] = 27, ["Parchemin"] = 27, ["두루마리"] = 27, ["Pergamino"] = 27, ["Свиток"] = 27, ["卷轴"] = 27, ["卷軸"] = 27,
    ["Other"] = 28, ["Sonstige"] = 28, ["Autre"] = 28, ["기타"] = 28, ["Otro"] = 28, ["Другое"] = 28, ["其它"] = 28,
    
    ["One-Handed Axes"] = 30, ["Einhandäxte"] = 30, ["Haches à une main"] = 30, ["한손 도끼류"] = 30, ["Hachas de Una Mano"] = 30, ["Одноручные топоры"] = 30, ["单手斧"] = 30, ["單手斧"] = 30,
    ["Two-Handed Axes"] = 31, ["Zweihandäxte"] = 31, ["Haches à deux mains"] = 31, ["양손 도끼류"] = 31, ["Hachas a Dos Manos"] = 31, ["Двуручные топоры"] = 31, ["双手斧"] = 31, ["雙手斧"] = 31,
    ["Bows"] = 32, ["Bögen"] = 32, ["Arcs"] = 32, ["활류"] = 32, ["Arcos"] = 32, ["Луки"] = 32, ["弓"] = 32,
    ["Guns"] = 33, ["Schusswaffen"] = 33, ["Fusils"] = 33, ["총기류"] = 33, ["Pistolas"] = 33, ["Огнестрельное"] = 33, ["枪械"] = 33, ["槍械"] = 33,
    ["One-Handed Maces"] = 34, ["Einhandstreitkolben"] = 34, ["Masses à une main"] = 34, ["한손 둔기류"] = 34, ["Mazas de Una Mano"] = 34, ["Одноручное дробящее"] = 34, ["单手锤"] = 34, ["單手錘"] = 34,
    ["Two-Handed Maces"] = 35, ["Zweihandstreitkolben"] = 35, ["Masses à deux mains"] = 35, ["양손 둔기류"] = 35, ["Mazas a Dos Manos"] = 35, ["Двуручное дробящее"] = 35, ["双手锤"] = 35, ["雙手錘"] = 35,
    ["Polearms"] = 36, ["Stangenwaffen"] = 36, ["Armes d'hast"] = 36, ["장창류"] = 36, ["Armas de asta"] = 36, ["Древковое"] = 36, ["长柄武器"] = 36, ["長柄武器"] = 36,
    ["One-Handed Swords"] = 37, ["Einhandschwerter"] = 37, ["Epées à une main"] = 37, ["한손 도검류"] = 37, ["Espadas de Una Mano"] = 37, ["Одноручные мечи"] = 37, ["单手剑"] = 37, ["單手劍"] = 37,
    ["Two-Handed Swords"] = 38, ["Zweihandschwerter"] = 38, ["Epées à deux mains"] = 38, ["양손 도검류"] = 38, ["Espadas a Dos Manos"] = 38, ["Двуручные мечи"] = 38, ["双手剑"] = 38, ["雙手劍"] = 38,
    ["Staves"] = 39, ["Stäbe"] = 39, ["Bâtons"] = 39, ["지팡이류"] = 39, ["Bastones"] = 39, ["Посохи"] = 39, ["法杖"] = 39,
    ["Fist Weapons"] = 40, ["Faustwaffen"] = 40, ["Armes de pugilat"] = 40, ["장착 무기류"] = 40, ["Armas de Puño"] = 40, ["Кистевое"] = 40, ["拳套"] = 40,
    ["Daggers"] = 41, ["Dolche"] = 41, ["Dagues"] = 41, ["단검류"] = 41, ["Dagas"] = 41, ["Кинжалы"] = 41, ["匕首"] = 41,
    ["Thrown"] = 42, ["Wurfwaffen"] = 42, ["Armes de jets"] = 42, ["투척 무기"] = 42, ["Arrojadiza"] = 42, ["Метательное"] = 42, ["投掷武器"] = 42, ["投擲武器"] = 42,
    ["Crossbows"] = 43, ["Armbrüste"] = 43, ["Arbalètes"] = 43, ["석궁류"] = 43, ["Ballestas"] = 43, ["Арбалеты"] = 43, ["弩"] = 43,
    ["Wands"] = 44, ["Zauberstäbe"] = 44, ["Baguettes"] = 44, ["마법봉류"] = 44, ["Varitas"] = 44, ["Жезлы"] = 44, ["魔杖"] = 44,
    ["Fishing Poles"] = 45, ["Angelruten"] = 45, ["Cannes à pêche"] = 45, ["낚싯대"] = 45, ["Cañas de pescar"] = 45, ["Удочки"] = 45, ["鱼竿"] = 45, ["魚竿"] = 45,
    
    ["Red"] = 50, ["Rot"] = 50, ["Rouge"] = 50, ["붉은색"] = 50, ["Rojo"] = 50, ["Красный"] = 50, ["红色"] = 50, ["紅色"] = 50,
    ["Blue"] = 51, ["Blau"] = 51, ["Bleu"] = 51, ["푸른색"] = 51, ["Azul"] = 51, ["Синий"] = 51, ["蓝色"] = 51, ["藍色"] = 51,
    ["Yellow"] = 52, ["Gelb"] = 52, ["Jaune"] = 52, ["노란색"] = 52, ["Amarillo"] = 52, ["Желтый"] = 52, ["黄色"] = 52, ["黃色"] = 52,
    ["Purple"] = 53, ["Violett"] = 53, ["Violette"] = 53, ["보라색"] = 53, ["Morado"] = 53, ["Фиолетовый"] = 53, ["紫色"] = 53,
    ["Orange"] = 55, ["오렌지"] = 55, ["Naranja"] = 55, ["Оранжевый"] = 55, ["橙色"] = 55, ["橘色"] = 55,
    ["Meta"] = 56, ["얼개"] = 56, ["Мета"] = 56, ["多彩"] = 56, ["變換"] = 56,
    ["Simple"] = 57, ["Einfach"] = 57, ["일반"] = 57, ["Простой"] = 57, ["简易"] = 57, ["簡單"] = 57,
    ["Prismatic"] = 58, ["Prismatisch"] = 58, ["다색"] = 58, ["Prismático"] = 58, ["Радужный"] = 58, ["棱彩"] = 58, ["稜彩"] = 58,
    
    ["Parts"] = 60, ["Teile"] = 60, ["Eléments"] = 60, ["부품"] = 60, ["Partes"] = 60, ["Детали"] = 60, ["零件"] = 60,
    ["Explosives"] = 61, ["Sprengstoff"] = 61, ["Explosifs"] = 61, ["폭탄"] = 61, ["Взрывчатка"] = 61, ["爆炸物"] = 61,
    ["Devices"] = 62, ["Geräte"] = 62, ["Appareils"] = 62, ["장치"] = 62, ["Dispositivos"] = 62, ["Устройства"] = 62, ["装置"] = 62,
    ["Jewelcrafting"] = 63, ["Juwelenschleifen"] = 63, ["Joaillerie"] = 63, ["보석세공"] = 63, ["Joyería"] = 63, ["Ювелирное дело"] = 63, ["珠宝加工"] = 63, ["珠寶設計"] = 63,
    ["Metal & Stone"] = 64, ["Metall & Stein"] = 64, ["Métal & pierre"] = 64, ["광물"] = 64, ["Metal y Piedra"] = 64, ["Металл и камень"] = 64, ["金属和矿石"] = 64, ["金屬與石頭"] = 64,
    ["Meat"] = 65, ["Fleisch"] = 65, ["Viande"] = 65, ["고기"] = 65, ["Carne"] = 65, ["Мясо"] = 65, ["肉类"] = 65, ["肉類"] = 65,
    ["Herb"] = 66, ["Kräuter"] = 66, ["Herbes"] = 66, ["약초"] = 66, ["Herbalísmo"] = 66, ["Трава"] = 66, ["草药"] = 66, ["草藥"] = 66,
    ["Elemental"] = 67, ["Elementar"] = 67, ["Élémentaire"] = 67, ["원소"] = 67, ["Стихии"] = 67, ["元素"] = 67, ["元素材料"] = 67,
    
    ["Book"] = 70, ["Buch"] = 70, ["Livre"] = 70, ["책"] = 70, ["Libro"] = 70, ["Книга"] = 70, ["书籍"] = 70, ["書籍"] = 70,
    ["Leatherworking"] = 71, ["Lederverarbeitung"] = 71, ["Travail du cuir"] = 71, ["가죽세공"] = 71, ["Peletería"] = 71, ["Кожевничество"] = 71, ["制皮"] = 71, ["製皮"] = 71,
    ["Tailoring"] = 72, ["Schneiderei"] = 72, ["Couture"] = 72, ["재봉술"] = 72, ["Sastrería"] = 72, ["Портняжное дело"] = 72, ["裁缝"] = 72, ["裁縫"] = 72,
    ["Engineering"] = 73, ["Ingenieurskunst"] = 73, ["Ingénierie"] = 73, ["기계공학"] = 73, ["Ingeniería"] = 73, ["Механика"] = 73, ["工程学"] = 73, ["工程學"] = 73,
    ["Blacksmithing"] = 74, ["Schmiedekunst"] = 74, ["Forge"] = 74, ["대장기술"] = 74, ["Herrería"] = 74, ["Кузнечное дело"] = 74, ["锻造"] = 74, ["鍛造"] = 74,
    ["Cooking"] = 75, ["Kochkunst"] = 75, ["Cuisine"] = 75, ["요리"] = 75, ["Cocina"] = 75, ["Кулинария"] = 75, ["烹饪"] = 75, ["烹飪"] = 75,
    ["Alchemy"] = 76, ["Alchimie"] = 76, ["연금술"] = 76, ["Alquimia"] = 76, ["Алхимия"] = 76, ["炼金术"] = 76, ["鍊金術"] = 76,
    ["First Aid"] = 77, ["Erste Hilfe"] = 77, ["Secourisme"] = 77, ["응급치료"] = 77, ["Primeros auxilios"] = 77, ["Первая помощь"] = 77, ["急救"] = 77,
    ["Enchanting"] = 78, ["Verzauberkunst"] = 78, ["마법부여"] = 78, ["Encantamiento"] = 78, ["Наложение чар"] = 78, ["附魔"] = 78,
    ["Fishing"] = 79, ["Angeln"] = 79, ["Pêche"] = 79, ["낚시"] = 79, ["Pesca"] = 79, ["Рыбная ловля"] = 79, ["钓鱼"] = 79, ["釣魚"] = 79,
    ["Miscellaneous"] = 80, ["其他"] = 80 
}

local ENGLISH_ITEM_TYPES = { "Armor", "Container", "Consumable", "Weapon", "Gem", "Trade Goods", "Reagent", "Recipe", "Projectile", "Quest", "Key", "Miscellaneous", "Glyph" }
local ENGLISH_ITEM_SUBTYPES = {
    
    "Cloth", "Leather", "Mail", "Plate", "Shields", "Librams", "Idols", "Totems", "Sigils",
    
    "Bag", "Soul Bag", "Herb Bag", "Enchanting Bag", "Engineering Bag", "Gem Bag", "Mining Bag", "Leatherworking Bag", "Inscription Bag", "Quiver", "Ammo Pouch",
    
    "Food & Drink", "Potion", "Elixir", "Flask", "Bandage", "Item Enhancement", "Scroll", "Other",
    
    "One-Handed Axes", "Two-Handed Axes", "Bows", "Guns", "One-Handed Maces", "Two-Handed Maces", "Polearms", "One-Handed Swords", "Two-Handed Swords",
    "Staves", "Fist Weapons", "Daggers", "Thrown", "Crossbows", "Wands", "Fishing Poles",
    
    "Red", "Blue", "Yellow", "Purple", "Green", "Orange", "Meta", "Simple", "Prismatic",
    
    "Parts", "Explosives", "Devices", "Jewelcrafting", "Metal & Stone", "Meat", "Herb", "Elemental",
    
    "Book", "Leatherworking", "Tailoring", "Engineering", "Blacksmithing", "Cooking", "Alchemy", "First Aid", "Enchanting", "Fishing", "Miscellaneous",
}

Constants.ID_TO_ITEM_TYPE = {}
for _, englishName in ipairs(ENGLISH_ITEM_TYPES) do
    local id = Constants.ITEM_TYPE_TO_ID[englishName]
    if id then
        Constants.ID_TO_ITEM_TYPE[id] = englishName
    end
end

Constants.ID_TO_ITEM_SUBTYPE = {}
for _, englishName in ipairs(ENGLISH_ITEM_SUBTYPES) do
    local id = Constants.ITEM_SUBTYPE_TO_ID[englishName]
    if id then
        
        
        
        if not Constants.ID_TO_ITEM_SUBTYPE[id] then
             Constants.ID_TO_ITEM_SUBTYPE[id] = englishName
        end
    end
end

Constants.CLASS_PROFICIENCIES = {
    WARRIOR = {
        armor = {1, 2, 3, 4, 5}, 
        weapons = {30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43}, 
    },
    PALADIN = {
        armor = {1, 2, 3, 4, 5, 6}, 
        weapons = {30, 31, 34, 35, 36, 37, 38}, 
    },
    HUNTER = {
        armor = {1, 2, 3}, 
        weapons = {30, 31, 32, 33, 36, 37, 38, 39, 40, 41, 43}, 
    },
    ROGUE = {
        armor = {1, 2}, 
        weapons = {32, 33, 34, 37, 40, 41, 42, 43}, 
    },
    PRIEST = {
        armor = {1}, 
        weapons = {34, 39, 41, 44}, 
    },
    DEATHKNIGHT = {
        armor = {1, 2, 3, 4, 9}, 
        weapons = {30, 31, 34, 35, 36, 37, 38}, 
    },
    SHAMAN = {
        armor = {1, 2, 3, 5, 8}, 
        weapons = {30, 31, 34, 35, 39, 40, 41}, 
    },
    MAGE = {
        armor = {1}, 
        weapons = {37, 39, 41, 44}, 
    },
    WARLOCK = {
        armor = {1}, 
        weapons = {37, 39, 41, 44}, 
    },
    DRUID = {
        armor = {1, 2, 7}, 
        weapons = {34, 35, 36, 39, 40, 41}, 
    },
}

Constants.HASH_SAP = "LC@Asc.BB25"
Constants.HASH_SEED = 2025

Constants.HASH_BLACKLIST = {
   
}

Constants.rHASH_BLACKLIST = {
	["f0f44edb"] = true, ["27f22c66"] = true, ["671cab01"] = true,	
}

Constants.cHASH_BLACKLIST = {
["051901b6"] = true, ["da238c3f"] = true, ["cff15644"] = true, ["9a060893"] = true,
	["2d013949"] = true, ["9eefc783"] = true, ["2f9f0f0a"] = true, ["7e10b250"] = true,
	["2e8deaa2"] = true, ["bc34aa4f"] = true, ["78cf4671"] = true, ["a9879922"] = true,
	["b641b413"] = true, ["4c6aab78"] = true,	["fb544442"] = true, ["21cd4aa4"] = true,
	["324397dd"] = true, ["4bbed387"] = true,	["a84cee53"] = true, ["51ac4ad6"] = true,
	["387c7ead"] = true, ["dab462d2"] = true, ["71b23c1d"] = true, ["89855da9"] = true,
	["b0c52c50"] = true, ["2064ff8b"] = true, ["9d113ac7"] = true, ["c42f0d64"] = true,
	["2ebc9926"] = true,  
	
	["8782f429"] = true, ["72aa2219"] = true, ["4c9ca17b"] = true, ["727c0172"] = true,
	["1d4fb044"] = true, ["e1be2c84"] = true, ["1b6c6c4b"] = true, ["d2f11f88"] = true,	
	["fe882c07"] = true, ["4837c8dd"] = true,
	
	["e6b20cbd"] = true, ["3e931c1f"] = true, ["810003a5"] = true, ["30d5d57f"] = true,
	["9ac1e6cd"] = true, ["a91117fc"] = true, ["d0ae0c62"] = true, ["e0d4f49b"] = true,	
	["dbe80f12"] = true, ["1bab3599"] = true, ["657ba6a3"] = true, ["a33da348"] = true,
	["ffe5ca8c"] = true,
}

Constants.iHASH_BLACKLIST = {
	["376eafb7"] = true, ["17cb02f0"] = true, ["f0f44edb"] = true, ["27f22c66"] = true, 	
	["21cd4aa4"] = true, ["f4f00527"] = true, ["324397dd"] = true, ["4bbed387"] = true, 
	["387c7ead"] = true, ["dab462d2"] = true, ["71b23c1d"] = true, ["015bea49"] = true,
	["6620c0ec"] = true, ["a84cee53"] = true, ["89855da9"] = true, ["7e10b250"] = true,	
	["fb544442"] = true, ["9672c459"] = true, ["30dd772f"] = true, ["cbd6682f"] = true, 	
	["dd8ece3c"] = true, ["8a250f52"] = true, ["d5309afa"] = true, ["cbe6f90c"] = true, 
	["051901b6"] = true, ["da238c3f"] = true, ["cff15644"] = true, ["9a060893"] = true,
	["2d013949"] = true, ["9eefc783"] = true, ["2f9f0f0a"] = true,
	["2e8deaa2"] = true, ["bc34aa4f"] = true, ["78cf4671"] = true, ["a9879922"] = true,
	["b641b413"] = true, ["4c6aab78"] = true, ["b0c52c50"] = true, ["2064ff8b"] = true,
	["2ebc9926"] = true, ["51ac4ad6"] = true, ["9d113ac7"] = true, ["c42f0d64"] = true,
    
}

Constants.NameHashCache = {}

function Constants.RoundTo(v, places)
    v = tonumber(v) or 0
    local mul = 10 ^ (places or 0)
    return math.floor(v * mul + 0.5) / mul
end

function Constants.RoundCoord(v)
    return Constants.RoundTo(v, Constants.COORD_PRECISION)
end

function Constants.IsValidOp(op)
    return op == Constants.OP.DISC or op == Constants.OP.CONF or op == Constants.OP.ACK
end

function Constants.IsValidAct(act)
    return act == Constants.ACT.DET or act == Constants.ACT.VER or act == Constants.ACT.SPM or act == Constants.ACT.DUP
end

function Constants:GetCachedNameHash(name)
    if not name or name == "" then return nil end
    if Constants.NameHashCache[name] then
        return Constants.NameHashCache[name]
    end
    
    if not XXH_Lua_Lib then return nil end
    
    local combined_str = name .. Constants.HASH_SAP
    local hash_val = XXH_Lua_Lib.XXH32(combined_str, Constants.HASH_SEED)
    local hex_hash = string.format("%08x", hash_val)
    
    Constants.NameHashCache[name] = hex_hash
    return hex_hash
end

function Constants:IsHashInList(name, listName)
    if not name or name == "" or not listName then return false end
    
    local blacklist = Constants[listName]
    if not blacklist or not next(blacklist) then return false end 
    
    local hex_hash = self:GetCachedNameHash(name)
    if not hex_hash then return false end
    
    return blacklist[hex_hash] == true
end

function Constants._DevOverridePrecision(n)
    if type(n) == "number" and n >= 0 and n <= 6 then
        Constants.COORD_PRECISION = math.floor(n)
    end
end

function Constants._DevOverrideCompression(level)
    if type(level) == "number" and level >= 1 and level <= 9 then
        Constants.DEFLATE_LEVEL = math.floor(level)
    end
end

function Constants._DevOverrideAckThreshold(n)
    if type(n) == "number" and n >= 1 and n <= 100 then
        Constants.ACK_HOLD_THRESHOLD = math.floor(n)
    end
end

function Constants:GetProtocolVersion()
    return Constants.PROTO_V
end

function Constants:GetMinCompatibleVersion()
    return Constants.MIN_COMPATIBLE_VERSION
end

function Constants:GetAllowedDiscoveryTypes()
    return Constants.ALLOWED_DISCOVERY_TYPES
end

function Constants:GetOp()
    return Constants.OP
end

function Constants:GetAct()
    return Constants.ACT
end

function Constants:GetStatusConstants()
    return Constants.STATUS
end

function Constants:GetCoordPrecision()
    return Constants.COORD_PRECISION
end

function Constants:GetMaxChatBytes()
    return Constants.MAX_CHAT_BYTES
end

function Constants:GetDeflateLevel()
    return Constants.DEFLATE_LEVEL
end

function Constants:GetSeenTtl()
    return Constants.SEEN_TTL_SECONDS
end

function Constants:GetCooldownTtl()
    return Constants.COOLDOWN_TTL
end

function Constants:GetChatMinInterval()
    return Constants.CHAT_MIN_INTERVAL
end

function Constants:GetAckHoldThreshold()
    return Constants.ACK_HOLD_THRESHOLD
end

function Constants:GetDefaultPrefix()
    return Constants.ADDON_PREFIX_DEFAULT
end

function Constants:GetDefaultChannel()
    return Constants.CHANNEL_NAME_DEFAULT
end

function Constants:OnInitialize()
    
end

return Constants
