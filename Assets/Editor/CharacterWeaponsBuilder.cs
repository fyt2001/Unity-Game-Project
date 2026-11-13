using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Animations;
using UnityEngine;

/// <summary>Reproducible first sword/pistol art and controller assembly.</summary>
public static class CharacterWeaponsBuilder
{
    const string Root = "Assets/Game/AssetsPackage/Characters/Weapons";
    const string ModelPath = "Assets/Game/AssetsPackage/Characters/Soldier_Male.fbx";
    const string Bundle = "characters/combatweapons.asset";

    [MenuItem("Tools/Characters/Rebuild Pistol Visual Only")]
    public static void RebuildPistolVisual()
    {
        if (EditorApplication.isPlaying) throw new InvalidOperationException("Stop Play before asset assembly.");
        if (!AssetDatabase.LoadAssetAtPath<GameObject>(Root + "/Pistol_Blender_01.fbx"))
            throw new InvalidOperationException("Blender pistol FBX must be imported before rebuilding.");
        var flash = AssetDatabase.LoadAssetAtPath<Material>(Root + "/WeaponFlash.mat");
        if (!flash) throw new InvalidOperationException("Existing muzzle flash material is missing.");
        BuildGun(null, null, null, flash);
        foreach (string name in new[] { "PistolBody.mat", "PistolTrim.mat", "PistolGrip.mat", "PistolFlash.mat", "PistolMuzzleFlash.asset", "Pistol_Blender_01.fbx", "Weapon_Pistol_01.prefab" })
            AssetImporter.GetAtPath(Root + "/" + name).assetBundleName = Bundle;
        AssetDatabase.SaveAssets();
    }

    [MenuItem("Tools/Characters/Build Combat Weapons")]
    public static void Build()
    {
        if (EditorApplication.isPlaying) throw new InvalidOperationException("Stop Play before asset assembly.");
        if (!AssetDatabase.LoadAssetAtPath<GameObject>(Root + "/Pistol_Blender_01.fbx"))
            throw new InvalidOperationException("Blender pistol FBX must be imported before rebuilding combat weapons.");
        Directory.CreateDirectory(Root); AssetDatabase.Refresh();
        var clips = AssetDatabase.LoadAllAssetsAtPath(ModelPath).OfType<AnimationClip>().ToArray();
        Func<string, AnimationClip> clip = name => clips.First(c => c.name == "CharacterArmature|" + name);
        var gun = clip("Shoot_OneHanded"); var slash = clip("SwordSlash");
        var gunHold = Pose(gun, "HoldPistol", 0.08f);
        var swordHold = Pose(slash, "HoldSword", 0.08f);
        var mask = LoadOrCreate<AvatarMask>("UpperBody.mask");
        var model = AssetDatabase.LoadAssetAtPath<GameObject>(ModelPath);
        mask.transformCount = 0;
        mask.AddTransformPath(model.transform, true);
        for (int i = 0; i < mask.transformCount; i++)
        {
            string path = mask.GetTransformPath(i);
            // Mask uses paths relative to Animator; strip imported root object name.
            if (path == model.name) path = "";
            else if (path.StartsWith(model.name + "/", StringComparison.Ordinal)) path = path.Substring(model.name.Length + 1);
            mask.SetTransformPath(i, path);
            mask.SetTransformActive(i, path.EndsWith("/Abdomen", StringComparison.Ordinal) || path.Contains("/Abdomen/"));
        }
        EditorUtility.SetDirty(mask);
        string controllerPath = Root + "/SoldierCombat.controller";
        var controller = AssetDatabase.LoadAssetAtPath<AnimatorController>(controllerPath);
        if (!controller) controller = AnimatorController.CreateAnimatorControllerAtPath(controllerPath);
        // Rebuild only this generated controller's state machines.
        foreach (var layer in controller.layers)
            foreach (var state in layer.stateMachine.states) layer.stateMachine.RemoveState(state.state);
        if (!controller.parameters.Any(p => p.name == "CombatSpeed")) controller.AddParameter("CombatSpeed", AnimatorControllerParameterType.Float);
        var baseSM = controller.layers[0].stateMachine;
        AddState(baseSM, "Stand", clip("Idle")); AddState(baseSM, "Walk", clip("Walk")); AddState(baseSM, "Run", clip("Run"));
        baseSM.defaultState = baseSM.states.First(s => s.state.name == "Stand").state;
        if (controller.layers.Length < 2) controller.AddLayer("CombatUpper");
        var layers = controller.layers;
        layers[1].name = "CombatUpper"; layers[1].avatarMask = mask;
        layers[1].defaultWeight = 0f; layers[1].blendingMode = AnimatorLayerBlendingMode.Override;
        controller.layers = layers;
        var upper = layers[1].stateMachine;
        AddState(upper, "HoldSword", swordHold); AddState(upper, "HoldPistol", gunHold);
        AddState(upper, "SwordSlash", slash, true); AddState(upper, "Shoot", gun, true);
        upper.defaultState = upper.states.First(s => s.state.name == "HoldPistol").state;
        EditorUtility.SetDirty(controller);

        var metal = Material("WeaponMetal", new Color(0.25f, 0.29f, 0.34f), 0.6f);
        var grip = Material("WeaponGrip", new Color(0.12f, 0.10f, 0.08f), 0.05f);
        var accent = Material("WeaponAccent", new Color(0.55f, 0.39f, 0.16f), 0.55f);
        var glow = Material("WeaponFlash", new Color(1f, 0.75f, 0.25f), 0f);
        glow.EnableKeyword("_EMISSION"); glow.SetColor("_EmissionColor", new Color(2.4f, 1.5f, 0.4f));
        var swordPrefab = BuildSword(metal, glow);
        var gunPrefab = BuildGun(metal, grip, accent, glow);
        var swordDef = Definition("Sword", swordPrefab, slash, "HoldSword", "SwordSlash", 0.28f);
        var gunDef = Definition("Pistol", gunPrefab, gun, "HoldPistol", "Shoot", 0.12f);
        swordDef.gripRotation = GripRotation(model, swordHold);
        gunDef.gripRotation = GripRotation(model, gunHold);
        EditorUtility.SetDirty(swordDef); EditorUtility.SetDirty(gunDef);
        foreach (string path in new[] { "Assets/Game/Prefabs/QuaterniusHero.prefab", "Assets/Game/Resources/Characters/QuaterniusHero.prefab" })
        {
            var root = PrefabUtility.LoadPrefabContents(path);
            try
            {
                var view = root.GetComponent<Model3DCharacterView>();
                view.animatorController = controller; view.swordWeapon = swordDef; view.pistolWeapon = gunDef;
                PrefabUtility.SaveAsPrefabAsset(root, path);
            }
            finally { PrefabUtility.UnloadPrefabContents(root); }
        }
        AssetDatabase.SaveAssets();
        foreach (string guid in AssetDatabase.FindAssets("", new[] {Root}))
        {
            string path = AssetDatabase.GUIDToAssetPath(guid);
            if (AssetDatabase.IsValidFolder(path)) continue;
            AssetImporter.GetAtPath(path).assetBundleName = Bundle;
        }
        AssetDatabase.SaveAssets();
        Debug.Log("[CharacterWeaponsBuilder] Sword, pistol, hand poses and combat layer built.");
    }

    static T LoadOrCreate<T>(string name) where T : UnityEngine.Object
    {
        string path = Root + "/" + name;
        var value = AssetDatabase.LoadAssetAtPath<T>(path);
        if (value) return value;
        value = typeof(T) == typeof(AvatarMask) ? new AvatarMask() as T : ScriptableObject.CreateInstance(typeof(T)) as T;
        AssetDatabase.CreateAsset(value, path); return value;
    }
    static AnimationClip Pose(AnimationClip source, string name, float time)
    {
        string path = Root + "/" + name + ".anim";
        var result = AssetDatabase.LoadAssetAtPath<AnimationClip>(path);
        if (!result) { result = new AnimationClip(); AssetDatabase.CreateAsset(result, path); }
        result.ClearCurves(); result.name = name; result.frameRate = 30;
        foreach (var binding in AnimationUtility.GetCurveBindings(source))
        {
            var curve = AnimationUtility.GetEditorCurve(source, binding);
            float value = curve.Evaluate(time);
            AnimationUtility.SetEditorCurve(result, binding, AnimationCurve.Constant(0, 1, value));
        }
        result.EnsureQuaternionContinuity();
        var settings = AnimationUtility.GetAnimationClipSettings(result); settings.loopTime = true;
        AnimationUtility.SetAnimationClipSettings(result, settings); EditorUtility.SetDirty(result); return result;
    }
    static void AddState(AnimatorStateMachine machine, string name, Motion motion, bool speed = false)
    {
        var state = machine.AddState(name); state.motion = motion;
        if (speed) { state.speedParameter = "CombatSpeed"; state.speedParameterActive = true; }
    }
    static Material Material(string name, Color color, float metallic)
    {
        string path = Root + "/" + name + ".mat";
        var material = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (!material) { material = new Material(Shader.Find("Standard")); AssetDatabase.CreateAsset(material, path); }
        material.color = color; material.SetFloat("_Metallic", metallic); material.SetFloat("_Glossiness", 0.35f);
        EditorUtility.SetDirty(material); return material;
    }
    static GameObject Part(GameObject root, string name, Vector3 position, Vector3 scale, Material material)
    {
        var part = GameObject.CreatePrimitive(PrimitiveType.Cube); part.name = name;
        UnityEngine.Object.DestroyImmediate(part.GetComponent<Collider>());
        part.transform.SetParent(root.transform, false); part.transform.localPosition = position; part.transform.localScale = scale;
        part.GetComponent<Renderer>().sharedMaterial = material; return part;
    }
    static Transform Anchor(GameObject parent, string name, Vector3 position)
    {
        var anchor = new GameObject(name).transform; anchor.SetParent(parent.transform, false); anchor.localPosition = position; return anchor;
    }
    static GameObject BuildGun(Material metal, Material grip, Material accent, Material flash)
    {
        var root = new GameObject("Weapon_Pistol_01");
        var source = AssetDatabase.LoadAssetAtPath<GameObject>(Root + "/Pistol_Blender_01.fbx");
        if (!source) throw new InvalidOperationException("Blender pistol FBX missing; existing prefab was not replaced.");
        var visual = UnityEngine.Object.Instantiate(source, root.transform, false);
        visual.name = "Visual";
        // FBX imports with barrel facing -Z; rotate only the visual into our +Z contract.
        visual.transform.localRotation = Quaternion.Euler(0, 180, 0) * visual.transform.localRotation;
        // Dedicated finishes keep the pistol legible without changing sword materials.
        var bodyFinish = PistolMaterial("PistolBody", new Color(0.50f, 0.57f, 0.63f), 0.22f, 0.48f);
        var trimFinish = PistolMaterial("PistolTrim", new Color(0.75f, 0.61f, 0.40f), 0.32f, 0.55f);
        var gripFinish = PistolMaterial("PistolGrip", new Color(0.26f, 0.30f, 0.33f), 0.02f, 0.25f);
        foreach (var renderer in visual.GetComponentsInChildren<Renderer>())
        {
            renderer.sharedMaterials = renderer.sharedMaterials.Select(material =>
            {
                if (material && material.name.StartsWith("Graphite", StringComparison.Ordinal)) return bodyFinish;
                if (material && material.name.StartsWith("Brass", StringComparison.Ordinal)) return trimFinish;
                if (material && material.name.StartsWith("Grip", StringComparison.Ordinal)) return gripFinish;
                throw new InvalidOperationException("Unexpected Blender pistol material; check model import.");
            }).ToArray();
        }
        var muzzle = Anchor(root, "Muzzle", new Vector3(0,0.104f,0.269f));
        var effect = CreatePistolFlash(muzzle);
        effect.SetActive(false); Anchor(root,"Grip_L",new Vector3(0,-0.02f,0.03f)); Anchor(root,"VFXRoot",Vector3.zero);
        return Save(root, "Weapon_Pistol_01.prefab");
    }
    static GameObject CreatePistolFlash(Transform muzzle)
    {
        string meshPath = Root + "/PistolMuzzleFlash.asset";
        var mesh = AssetDatabase.LoadAssetAtPath<Mesh>(meshPath);
        if (!mesh) { mesh = new Mesh(); AssetDatabase.CreateAsset(mesh, meshPath); }
        mesh.Clear(); mesh.name = "PistolMuzzleFlash";
        var vertices = new Vector3[10]; var colors = new Color[10]; var triangles = new int[48];
        vertices[0] = Vector3.zero; vertices[9] = new Vector3(0, 0, 0.065f);
        colors[0] = colors[9] = new Color(1, 1, 1, 0);
        for (int i = 0; i < 8; i++)
        {
            float angle = i * Mathf.PI / 4f; float radius = i % 2 == 0 ? 0.020f : 0.008f;
            vertices[i + 1] = new Vector3(Mathf.Cos(angle) * radius, Mathf.Sin(angle) * radius, 0.018f);
            colors[i + 1] = new Color(1, 0.95f, 0.70f, 0.8f);
            int next = (i + 1) % 8 + 1; int t = i * 6;
            triangles[t] = 0; triangles[t + 1] = next; triangles[t + 2] = i + 1;
            triangles[t + 3] = i + 1; triangles[t + 4] = next; triangles[t + 5] = 9;
        }
        mesh.vertices = vertices; mesh.colors = colors; mesh.triangles = triangles;
        mesh.RecalculateNormals(); mesh.RecalculateBounds(); EditorUtility.SetDirty(mesh);
        string materialPath = Root + "/PistolFlash.mat";
        var material = AssetDatabase.LoadAssetAtPath<Material>(materialPath);
        var shader = Shader.Find("Legacy Shaders/Particles/Additive");
        if (!shader) shader = Shader.Find("Particles/Additive");
        if (!shader) throw new InvalidOperationException("Additive muzzle flash shader is unavailable.");
        if (!material) { material = new Material(shader); AssetDatabase.CreateAsset(material, materialPath); }
        material.shader = shader; material.SetColor("_TintColor", new Color(1, 0.80f, 0.40f, 0.8f));
        EditorUtility.SetDirty(material);
        var effect = new GameObject("MuzzleFlash"); effect.transform.SetParent(muzzle, false);
        effect.transform.localPosition = new Vector3(0, 0, 0.002f);
        effect.AddComponent<MeshFilter>().sharedMesh = mesh;
        var renderer = effect.AddComponent<MeshRenderer>(); renderer.sharedMaterial = material;
        renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        renderer.receiveShadows = false;
        return effect;
    }
    static Material PistolMaterial(string name, Color color, float metallic, float smoothness)
    {
        var material = Material(name, color, metallic);
        material.SetFloat("_Glossiness", smoothness);
        // A very small readability floor for scenes without reflection probes.
        material.EnableKeyword("_EMISSION");
        material.SetColor("_EmissionColor", color * 0.035f);
        EditorUtility.SetDirty(material);
        return material;
    }
    static GameObject BuildSword(Material metal, Material glow)
    {
        var root = new GameObject("Weapon_Sword_01");
        var source = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Game/Resources/VFX/FlyingSword/Models/Sword_1H.fbx");
        if (!source) throw new InvalidOperationException("Existing sword FBX missing.");
        var visual = UnityEngine.Object.Instantiate(source,root.transform,false); visual.name = "Visual";
        visual.transform.localRotation = Quaternion.Euler(90,0,0); visual.transform.localScale = Vector3.one * 0.52f;
        foreach(var renderer in visual.GetComponentsInChildren<Renderer>()) renderer.sharedMaterial = metal;
        Anchor(root,"BladeRoot",new Vector3(0,0,0.12f)); var tip=Anchor(root,"BladeTip",new Vector3(0,0,0.73f));
        Anchor(root,"VFXRoot",Vector3.zero);
        var trail=tip.gameObject.AddComponent<TrailRenderer>(); trail.sharedMaterial=glow;
        trail.time=0.12f; trail.startWidth=0.055f; trail.endWidth=0f; trail.emitting=false;
        trail.shadowCastingMode=UnityEngine.Rendering.ShadowCastingMode.Off;
        return Save(root,"Weapon_Sword_01.prefab");
    }
    static GameObject Save(GameObject root,string file)
    {
        try { return PrefabUtility.SaveAsPrefabAsset(root,Root+"/"+file); }
        finally { UnityEngine.Object.DestroyImmediate(root); }
    }
    static WeaponVisualDefinition Definition(string name, GameObject prefab,AnimationClip clip,string hold,string attack,float release)
    {
        var definition=LoadOrCreate<WeaponVisualDefinition>(name+".asset");
        definition.prefab=prefab; definition.attackClip=clip; definition.holdState=hold;
        definition.attackState=attack; definition.releaseFraction=release;
        definition.maximumAnimationSpeed=name=="Sword"?2f:2.5f;
        return definition;
    }
    static Vector3 GripRotation(GameObject prefab,AnimationClip pose)
    {
        var model=UnityEngine.Object.Instantiate(prefab);
        try
        {
            pose.SampleAnimation(model,0);
            var bones=model.GetComponentsInChildren<Transform>();
            Func<string,Transform> bone=n=>bones.First(t=>t.name==n);
            var up=(bone("Head").position-bone("Hips").position).normalized;
            var right=(bone("Shoulder.R").position-bone("Shoulder.L").position).normalized;
            var forward=Vector3.Cross(right,up).normalized;
            return (Quaternion.Inverse(bone("Fist.R").rotation)*Quaternion.LookRotation(forward,up)).eulerAngles;
        }
        finally { UnityEngine.Object.DestroyImmediate(model); }
    }
}
