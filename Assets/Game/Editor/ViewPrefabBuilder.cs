// =============================================================================
// ViewPrefabBuilder.cs  (Editor only)
// =============================================================================
// 一键生成战斗表现层所需的真实 prefab（子弹 / 掉落物）。
// 运行方式：Unity 菜单 Tools/Battle/Generate View Prefabs
//
// 说明：
//   - 敌人/怪物复用现有人形模型（在 HomeSceneBootstrapper 的 enemyModelPrefab 字段拖入
//     QuaterniusHero / BaseCharacter 等），无需本工具生成。
//   - 子弹 / 掉落物此前没有现成 prefab，这里生成规范预制体；生成后到
//     HomeSceneBootstrapper 对应字段（bulletPlayerPrefab / bulletEnemyPrefab /
//     dropWeaponPrefab / dropMaterialPrefab / dropItemPrefab）拖入即可。
//   - 未生成 / 未拖入时，Lua 视图（BulletView/DropView）会自动降级为基础几何体，逻辑不崩。
// =============================================================================

#if UNITY_EDITOR
using System.Linq;
using UnityEngine;
using UnityEditor;
using UnityEditor.Animations;

namespace Game.EditorTools
{
    public static class ViewPrefabBuilder
    {
        private const string OutDir = "Assets/Game/Prefabs/BattleViews";

        [MenuItem("Tools/Battle/Generate View Prefabs")]
        public static void Generate()
        {
            if (!AssetDatabase.IsValidFolder(OutDir))
                AssetDatabase.CreateFolder("Assets/Game/Prefabs", "BattleViews");

            BuildEnemyController();   // 先补齐含 Death/Hit 的敌人动画控制器
            BuildEnemyModel();        // 从模型库拿带动作的人形，生成 Resources/Characters/EnemyModel.prefab
            BuildBullet("BulletPlayer", new Color(1f, 0.85f, 0.2f), 0.8f);
            BuildBullet("BulletEnemy", new Color(1f, 0.3f, 0.25f), 0.8f);
            BuildDropWeapon("DropWeapon");
            BuildDropMaterial("DropMaterial");
            BuildDropItem("DropItem");

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
            Debug.Log("[ViewPrefabBuilder] 战斗表现 prefab 已生成到 " + OutDir);
        }

        // =============================================================================
        // 敌人动画控制器：模型库自带的 BaseCharacterController 只接了
        //   Stand / Walk / Run / Punch / SwordSlash / Shoot_OneHanded
        // 【没有死亡和受击状态】，敌人被打死只能「直接消失」。
        // 而 BaseCharacter.fbx 里本来就有 Death / RecieveHit / Defeat 等现成动作，
        // 这里复制一份 controller 并把它们接成状态，倒地表现交给美术的动作来做，
        // 不去手写程序化塌陷。Resources 下才能被运行时 Instantiate 后生效。
        // =============================================================================
        private const string EnemyCtrlPath  = "Assets/Game/Resources/Characters/EnemyController.controller";
        private const string EnemyModelPath = "Assets/Game/Resources/Characters/EnemyModel.prefab";

        /// <summary>
        /// 确保敌人模型与动画控制器存在；缺哪个补哪个（仅编辑器）。
        /// 产物随仓库提交后本来就在，这里只是兜底 —— 让开发者拿到仓库后
        /// 不必记得手动点 Tools/Battle/Generate View Prefabs。
        /// ⚠ 运行时无法创建 AnimatorController（UnityEditor.Animations 不可用），
        ///   所以打包前仍必须生成一次产物。
        /// </summary>
        public static void EnsureEnemyAssetsExist()
        {
            bool missCtrl  = AssetDatabase.LoadAssetAtPath<RuntimeAnimatorController>(EnemyCtrlPath) == null;
            bool missModel = AssetDatabase.LoadAssetAtPath<GameObject>(EnemyModelPath) == null;
            if (!missCtrl && !missModel) return;

            if (missCtrl) BuildEnemyController();
            // 控制器重建过的话模型也要重建，否则模型还引用旧 controller
            BuildEnemyModel();

            Debug.Log("[ViewPrefabBuilder] 自动补齐缺失的战斗表现资源 (ctrl=" + missCtrl + ", model=" + missModel + ")");
        }

        /// <summary>按名字从生成目录取一个 prefab（供 Inspector 未手拖时兜底）。</summary>
        public static GameObject LoadBattleViewPrefab(string name)
        {
            return AssetDatabase.LoadAssetAtPath<GameObject>(OutDir + "/" + name + ".prefab");
        }

        [MenuItem("Tools/Battle/Generate Enemy Animation Controller")]
        public static void BuildEnemyController()
        {
            const string ctrlSrc = "Assets/Game/AssetsPackage/Characters/BaseCharacterController.controller";
            const string fbxPath = "Assets/Game/AssetsPackage/Characters/BaseCharacter.fbx";

            if (!AssetDatabase.CopyAsset(ctrlSrc, EnemyCtrlPath))
            {
                Debug.LogError("[ViewPrefabBuilder] 复制基础控制器失败: " + ctrlSrc);
                return;
            }
            AssetDatabase.ImportAsset(EnemyCtrlPath);

            var ctrl = AssetDatabase.LoadAssetAtPath<AnimatorController>(EnemyCtrlPath);
            if (ctrl == null || ctrl.layers == null || ctrl.layers.Length == 0)
            {
                Debug.LogError("[ViewPrefabBuilder] 敌人动画控制器无效: " + EnemyCtrlPath);
                return;
            }

            // FBX 子资源里的动作：clip 名形如 "CharacterArmature|Death"，按后缀匹配
            var clips = AssetDatabase.LoadAllAssetsAtPath(fbxPath)
                .OfType<AnimationClip>()
                .ToArray();

            var wanted = new (string clipSuffix, string stateName, string returnTo)[]
            {
                // 死亡：停在最后一帧，不回 locomotion（尸体留存）
                ("Death", "Death", null),
                ("Defeat", "Defeat", null),
                // 受击：一次性动作，必须能自己回到 locomotion，否则会永久卡在最后一帧
                ("RecieveHit", "Hit", LocoStateName),
            };

            var sm = ctrl.layers[0].stateMachine;

            // 先把 locomotion 换成受 Speed 驱动的 BlendTree（会移除旧 Stand/Walk/Run 状态）
            var loco = BuildLocomotion(ctrl, sm, clips);

            int added = 0;

            foreach (var w in wanted)
            {
                var clip = clips.FirstOrDefault(c => c != null && c.name.EndsWith(w.clipSuffix));
                if (clip == null)
                {
                    Debug.LogWarning("[ViewPrefabBuilder] fbx 里找不到动作 " + w.clipSuffix);
                    continue;
                }
                if (sm.states.Any(s => s.state != null && s.state.name == w.stateName))
                    continue;   // 已存在则跳过，重跑不会重复添加

                var st = sm.AddState(w.stateName);
                st.motion = clip;
                added++;

                // 资源里的 Punch / Shoot_OneHanded 本来就自带出边回到 Walk；
                // 新增的受击状态没有，这里补一条同样的出边，让状态机自己复位。
                if (w.returnTo != null)
                {
                    var back = sm.states.FirstOrDefault(s => s.state != null && s.state.name == w.returnTo);
                    if (back.state != null)
                    {
                        var tr = st.AddTransition(back.state);
                        tr.hasExitTime = true;
                        tr.exitTime = 1f;
                        tr.duration = 0.1f;
                        tr.hasFixedDuration = true;
                        tr.conditions = new AnimatorCondition[0];
                    }
                    else
                    {
                        Debug.LogWarning("[ViewPrefabBuilder] 找不到回落状态 " + w.returnTo);
                    }
                }
            }

            EditorUtility.SetDirty(ctrl);
            AssetDatabase.SaveAssets();
            Debug.Log($"[ViewPrefabBuilder] 敌人动画控制器已生成: {EnemyCtrlPath}（新增 {added} 个状态）");
        }

        // =============================================================================
        // Locomotion：资源自带的 Stand / Walk / Run 是「分散状态 + 一对空条件且
        // HasExitTime=0 的双向 transition」，会在两者间无限乒乓 —— 敌人站着不动也在抽动，
        // 没法依据移动状态切换。这里删掉这三个状态，改成 1D BlendTree，
        // 由 Animator 的 Speed（浮点）参数在 Stand/Walk/Run 之间混合。
        // =============================================================================
        private const string LocoParam     = "Speed";        // BlendTree 混合参数
        private const string LocoStateName = "Locomotion";   // BlendTree 所在状态的名称

        /// <summary>各 BlendTree child 的速度阈值（单位/秒），按敌人实际 moveSpeed 调整。</summary>
        private static readonly float[] LocoThresholds = { 0f, 2f, 4f };   // Stand / Walk / Run

        private static AnimatorState BuildLocomotion(
            AnimatorController ctrl, AnimatorStateMachine sm, AnimationClip[] clips)
        {
            AnimationClip Find(string n) =>
                clips.FirstOrDefault(c => c != null && c.name.EndsWith(n));

            var stand = Find("Stand");
            var walk  = Find("Walk");
            var run   = Find("Run");
            if (stand == null && walk == null && run == null) return null;

            // 记录「指向待删状态」的过渡，稍后改指到 Locomotion，
            // 否则攻击/受击动作播完会落到已被移除的状态上。
            var removable = sm.states
                .Where(s => s.state != null && (s.state.name == "Stand" || s.state.name == "Walk" || s.state.name == "Run"))
                .Select(s => s.state).ToArray();

            var redirect = new System.Collections.Generic.List<AnimatorStateTransition>();
            foreach (var s in sm.states)
            {
                if (s.state == null || removable.Contains(s.state)) continue;
                foreach (var tr in s.state.transitions)
                {
                    if (tr != null && tr.destinationState != null && removable.Contains(tr.destinationState))
                        redirect.Add(tr);
                }
            }

            foreach (var st in removable) sm.RemoveState(st);

            if (ctrl.parameters.All(p => p.name != LocoParam))
                ctrl.AddParameter(LocoParam, AnimatorControllerParameterType.Float);

            var loco = sm.AddState(LocoStateName);
            loco.motion = BuildBlendTree(ctrl, stand, walk, run);
            foreach (var tr in redirect) tr.destinationState = loco;

            sm.defaultState = loco;   // 实例化后直接交给 BlendTree，不再播 Walk
            return loco;
        }

        private static BlendTree BuildBlendTree(
            AnimatorController ctrl, AnimationClip stand, AnimationClip walk, AnimationClip run)
        {
            var bt = new BlendTree
            {
                name             = LocoStateName,
                blendType        = BlendTreeType.Simple1D,
                blendParameter   = LocoParam,
                useAutomaticThresholds = false,
            };

            var children = new System.Collections.Generic.List<ChildMotion>();
            AddChild(children, stand, LocoThresholds[0]);
            AddChild(children, walk,  LocoThresholds[1]);
            AddChild(children, run,   LocoThresholds[2]);
            bt.children = children.ToArray();

            // 必须挂到 controller 资产上，否则 SaveAssets 后这个 BlendTree 不会被序列化
            AssetDatabase.AddObjectToAsset(bt, ctrl);
            return bt;
        }

        private static void AddChild(
            System.Collections.Generic.List<ChildMotion> list, AnimationClip clip, float threshold)
        {
            if (clip == null) return;
            list.Add(new ChildMotion
            {
                motion     = clip,
                threshold  = threshold,
                timeScale  = 1f,
                cycleOffset = 0f,
                mirror     = false,
                position   = Vector2.zero,
            });
        }

        // =============================================================================
        // 敌人模型：从模型库（AssetsPackage/Characters）拿一个带骨架动画的人形 fbx，
        // 配好 Animator + AnimatorController，生成可被运行时 Resources.Load 的 prefab。
        // 这样敌人实例化后就会自动播放 Stand/Walk/Run 动作（不再像 QuaterniusHero 那样没动作）。
        // 兵种差异仍由 Lua 侧 Tint 染色 + 缩放区分。
        // =============================================================================
        private static void BuildEnemyModel()
        {
            const string fbxPath  = "Assets/Game/AssetsPackage/Characters/BaseCharacter.fbx";
            const string ctrlPath = "Assets/Game/AssetsPackage/Characters/BaseCharacterController.controller";
            const string outDir   = "Assets/Game/Resources/Characters";

            var fbx = AssetDatabase.LoadAssetAtPath<GameObject>(fbxPath);
            if (fbx == null) { Debug.LogError("[ViewPrefabBuilder] 找不到敌人模型 fbx: " + fbxPath); return; }

            // 优先用补齐了 Death/Hit 的控制器；没有才退回原始 BaseCharacterController
            var ctrl = AssetDatabase.LoadAssetAtPath<RuntimeAnimatorController>(EnemyCtrlPath);
            if (ctrl == null)
            {
                BuildEnemyController();
                ctrl = AssetDatabase.LoadAssetAtPath<RuntimeAnimatorController>(EnemyCtrlPath);
            }
            if (ctrl == null) ctrl = AssetDatabase.LoadAssetAtPath<RuntimeAnimatorController>(ctrlPath);
            if (ctrl == null) { Debug.LogError("[ViewPrefabBuilder] 找不到敌人动画控制器"); return; }

            if (!AssetDatabase.IsValidFolder(outDir))
                AssetDatabase.CreateFolder("Assets/Game/Resources", "Characters");

            var inst = Object.Instantiate(fbx);
            var animator = inst.GetComponent<Animator>();
            if (animator == null) animator = inst.AddComponent<Animator>();
            animator.runtimeAnimatorController = ctrl;   // 含 Stand / Walk / Run，默认播 Stand 并自动循环
            animator.applyRootMotion = false;            // 位置由 Lua 每帧驱动，避免动画位移冲突
            animator.updateMode = AnimatorUpdateMode.Normal;
            animator.cullingMode = AnimatorCullingMode.CullCompletely;

            var prefab = PrefabUtility.SaveAsPrefabAsset(inst, EnemyModelPath);
            if (prefab == null) Debug.LogError("[ViewPrefabBuilder] 保存敌人模型 prefab 失败: " + EnemyModelPath);
            Object.DestroyImmediate(inst);
            Debug.Log("[ViewPrefabBuilder] 敌人模型 prefab 已生成: " + EnemyModelPath + " (动画=" + ctrl.name + ")");
        }

        private static void BuildBullet(string name, Color color, float emissiveK)
        {
            var go = new GameObject(name);
            var sphere = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            sphere.name = "Body";
            sphere.transform.SetParent(go.transform, false);
            sphere.transform.localScale = Vector3.one * 0.4f;
            ApplyEmissive(sphere, color, emissiveK);
            SaveAndDestroy(go, name);
        }

        private static void BuildDropWeapon(string name)
        {
            var go = new GameObject(name);
            var blade = GameObject.CreatePrimitive(PrimitiveType.Cube);
            blade.name = "Blade";
            blade.transform.SetParent(go.transform, false);
            blade.transform.localScale = new Vector3(0.12f, 0.7f, 0.12f);
            blade.transform.localPosition = new Vector3(0, 0.35f, 0f);
            ApplyEmissive(blade, new Color(0.5f, 0.9f, 1f), 0.6f);
            var guard = GameObject.CreatePrimitive(PrimitiveType.Cube);
            guard.name = "Guard";
            guard.transform.SetParent(go.transform, false);
            guard.transform.localScale = new Vector3(0.4f, 0.1f, 0.1f);
            ApplyEmissive(guard, new Color(0.7f, 0.6f, 0.2f), 0.3f);
            SaveAndDestroy(go, name);
        }

        private static void BuildDropMaterial(string name)
        {
            var go = new GameObject(name);
            var m = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            m.name = "Gem";
            m.transform.SetParent(go.transform, false);
            m.transform.localScale = Vector3.one * 0.45f;
            ApplyEmissive(m, new Color(0.3f, 0.9f, 0.4f), 0.6f);
            SaveAndDestroy(go, name);
        }

        private static void BuildDropItem(string name)
        {
            var go = new GameObject(name);
            var box = GameObject.CreatePrimitive(PrimitiveType.Cube);
            box.name = "Box";
            box.transform.SetParent(go.transform, false);
            box.transform.localScale = Vector3.one * 0.5f;
            ApplyEmissive(box, new Color(1f, 0.85f, 0.2f), 0.6f);
            SaveAndDestroy(go, name);
        }

        private static void ApplyEmissive(GameObject go, Color color, float k)
        {
            var r = go.GetComponent<Renderer>();
            if (r == null) return;
            r.sharedMaterial.color = color;
            r.sharedMaterial.EnableKeyword("_EMISSION");
            r.sharedMaterial.SetColor("_EmissionColor", color * k);
        }

        private static void SaveAndDestroy(GameObject go, string name)
        {
            var path = OutDir + "/" + name + ".prefab";
            var prefab = PrefabUtility.SaveAsPrefabAsset(go, path);
            if (prefab == null)
                Debug.LogError("[ViewPrefabBuilder] 保存失败: " + path);
            Object.DestroyImmediate(go);
        }
    }
}
#endif
