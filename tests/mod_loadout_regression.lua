local Save = require 'Game.Save.SaveData'
local Mods = require 'Game.Mod.ModSystem'
local Inv = require 'Game.Mod.ModInventory'
local Config = require 'Game.Mod.ModConfig'
local Model = require 'Game.UI.Mod.UIModStationModel'
local Controller = require 'Game.UI.Mod.UIModStationController'
local Player = require 'Game.Battle.PlayerController'
local Weapons = require 'Game.Battle.WeaponSystem'
local Build = require 'Game.Build.BuildSystem'
local old, commit = Save.current, Save.Commit
local commits = 0
local ok, result = xpcall(function()
    Save.current = Save.Default()
    Save.Commit = function() commits = commits + 1; return true end
    Save.current.inventory.mods = {
        {uid=1,id=1001,rank=1}, {uid=2,id=1001,rank=2},
        {uid=3,id=1002,rank=1}, {uid=4,id=1003,rank=1},
        {uid=5,id=2001,rank=1}, {uid=6,id=2002,rank=1},
        {uid=7,id=3001,rank=1}, {uid=8,id=3002,rank=1},
    }
    assert(Mods.EffectiveCost(Config.Get(1003),1,'Neutral') == 6, 'neutral discount')
    assert(Mods.EffectiveCost(Config.Get(1002),1,'Bone') == 2, 'round up')
    assert(Mods.Install('weapon',1,1))
    local allowed, reason = Mods.CanInstall('weapon',2,2)
    assert(not allowed and reason=='duplicate_mod')
    assert(Mods.Install('weapon',2,1), 'replace same type')
    assert(Mods.Install('weapon',2,2), 'move')
    assert(Save.current.loadout.weapon.installed[1]==nil)
    assert(Mods.Uninstall('weapon',2))
    assert(Mods.Install('weapon',1,1))
    assert(Mods.Install('weapon',3,2))
    assert(Mods.Install('weapon',4,3))
    assert(Mods.TotalUsed('weapon')==10)
    assert(not Mods.Install('weapon',1,2), 'moving to wrong polarity exceeds capacity')
    assert(Save.current.loadout.weapon.installed[1]==1)
    assert(not Inv.Upgrade(Inv.GetByUid(4)), 'upgrade must enforce installed capacity')
    assert(Inv.GetByUid(4).rank==1)
    Save.current.loadout.weapon.capacity=0
    assert(Inv.CanUpgrade(Inv.GetByUid(8)), 'unrelated host must not block upgrades')
    assert(Inv.UpgradeRandom(), 'random upgrade must find an eligible card')
    Inv.GetByUid(2).rank=2
    Inv.GetByUid(8).rank=1
    Inv.GetByUid(5).rank=1
    Inv.GetByUid(6).rank=1
    Inv.GetByUid(7).rank=1
    Save.current.loadout.weapon.capacity=10
    local previous=Save.current.loadout.weapon.installed
    Save.Commit=function() return false end
    assert(not Mods.Uninstall('weapon',3))
    assert(Save.current.loadout.weapon.installed==previous, 'failed save rollback')
    Save.Commit=function() commits=commits+1; return true end
    assert(not Mods.Install('frame',5,1), 'category')
    assert(not Mods.Install('frame',8,2), 'core restriction')
    assert(Mods.Install('skill',5,1))
    assert(Mods.Install('skill',6,2))
    assert(Mods.Install('frame',7,2))
    assert(Mods.Install('frame',8,1))
    Save.current.loadout.frame.capacity=0
    assert(not Mods.Uninstall('frame',2), 'core dependency')
    Save.current.loadout.frame.capacity=10
    Save.current.loadout.weapon.capacity=11
    local model=Model.New('ModStationPanel')
    assert(#model:GetBagItems()==4, 'category filter')
    local renders=0
    local ctrl=setmetatable({model=model,view={Render=function() renders=renders+1 end}}, {__index=Controller})
    ctrl:_onBagItem(2); ctrl:_onSlot(1)
    assert(Save.current.loadout.weapon.installed[1]==2, 'controller replacement')
    assert(model:GetSelected()==nil and model:GetFeedback()=='装配已保存')
    ctrl:_onBagItem(4); ctrl:_onBagItem(4)
    assert(model:GetSelected()==nil, 'toggle selection')
    assert(model:SetHost('skill') and #model:GetBagItems()==2)
    assert(model:SetHost('frame') and #model:GetBagItems()==2)
    assert(renders>=4)
    -- Shared instances can be referenced by different compatible hosts, never duplicated within one.
    local universal={id=9901,name='Test',category='Universal',polarity='Neutral',baseDrain=0,
        effect={stat='maxHp',mode='add',base=0,perRank=1}}
    Config[9901]=universal
    Save.current.inventory.mods[#Save.current.inventory.mods+1]={uid=99,id=9901,rank=1}
    assert(Mods.Install('weapon',99,3) and Mods.Install('skill',99,1))
    Config[9901]=nil
    Save.current.loadout.weapon.installed[3]=4
    Save.current.loadout.skill.installed[1]=5
    local derived=Mods.ComputeDerived()
    local pc=Player.New()
    local atk,hp,speed=pc.atk,pc.maxHp,pc.moveSpeed
    Mods.ApplyToPlayer(pc,derived)
    assert(math.abs(pc.atk-atk*1.2)<0.0001 and pc.maxHp==hp+20)
    assert(math.abs(pc.atkSpeed-1.15)<0.0001 and math.abs(pc.moveSpeed-speed*1.06)<0.0001)
    assert(math.abs(pc.critDmg-1.5*1.2)<0.0001)
    local ws=Weapons.New(); ws:Init(pc)
    local bs=Build.New(); bs:Init({build={weapons={},skills={},relics={}}}); bs:SetDerived(derived)
    local bm={weaponSystem=ws,playerController=pc}
    assert(bs:GrantStartingWeapon(bm))
    assert(ws.weapons[1].count==2, 'multishot applied')
    local shots=0
    ws.bulletManager={SpawnBullet=function(_,b) shots=shots+1; assert(b.damage>0) end}
    ws.enemyManager={GetNearestEnemies=function() return {{x=3,y=0}} end}
    ws:_attackProjectile(ws.weapons[1],0,0,10,false,{})
    assert(shots==2, 'one target still receives both shots')
    local drops=require('Game.Battle.DropSystem').New(); drops:Init(ws)
    drops:_pickup({kind='weapon',refId='w_firebolt'})
    assert(ws.weapons[2].count==2 and math.abs(ws.weapons[2].damage-16*1.2)<0.0001, 'drop modifiers')
    ws:SetModDerived(derived)
    assert(ws.weapons[1].count==2 and ws.weapons[2].count==2, 'idempotent modifiers')
    local serialized=require('Game.Save.SaveManager')._serialize(Save.current)
    local roundtrip=require('Game.Save.SaveManager')._deserialize(serialized)
    assert(roundtrip.loadout.weapon.installed[1]==2 and roundtrip.inventory.mods[4].rank==1)
    return 'PASS: replace/move, duplicate prevention, polarity rounding, full capacity, failed save rollback, core dependency, upgrade guard, UI controller/filter, player stats, two actual bullets, serialization; commits='..commits
end, debug.traceback)
Config[9901]=nil
Save.current,Save.Commit=old,commit
assert(ok,result)
return result
