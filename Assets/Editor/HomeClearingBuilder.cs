using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

public static class HomeClearingBuilder
{
    private const string Folder = "Assets/Game/Environment/HomeClearing";
    private const string HomePath = "Assets/Scenes/HomeScene.unity";
    private const int Seed = 61008;

    [MenuItem("Tools/Home Clearing/Build Ground And Lighting")]
    public static void Build()
    {
        if (EditorApplication.isPlaying)
            throw new InvalidOperationException("Stop Play Mode before building the clearing.");
        var scene = SceneManager.GetActiveScene();
        if (scene.path != HomePath || scene.isDirty)
            throw new InvalidOperationException("Open a saved HomeScene before building.");
        HomeSceneBootstrapper bootstrap = null;
        foreach (var item in scene.GetRootGameObjects())
        {
            var candidate = item.GetComponentInChildren<HomeSceneBootstrapper>();
            if (candidate != null) bootstrap = candidate;
        }
        if (bootstrap == null || bootstrap.startBattle)
            throw new InvalidOperationException("The non-battle Home bootstrapper is required.");
        var existing = bootstrap.GetComponent<HomeClearingEnvironment>();
        if (existing != null)
            throw new InvalidOperationException("Clearing already exists. Review it before rebuilding.");
        var shader = Shader.Find("Game/HomeClearing/Ground");
        if (shader == null || Shader.Find("Standard") == null)
            throw new InvalidOperationException("Required ground and Standard shaders are missing.");
        if (AssetDatabase.LoadAssetAtPath<Material>(Folder + "/Ground.mat") != null)
            throw new InvalidOperationException("Owned assets already exist; do not overwrite them.");

        var random = new System.Random(Seed);
        var root = new GameObject("HomeClearing_Prototype");
        SceneManager.MoveGameObjectToScene(root, scene);
        var groundMaterial = new Material(shader) { name = "Clearing Ground" };
        groundMaterial.SetColor("_Soil", new Color(0.43f, 0.39f, 0.31f));
        groundMaterial.SetColor("_Grass", new Color(0.30f, 0.40f, 0.20f));
        AssetDatabase.CreateAsset(groundMaterial, Folder + "/Ground.mat");
        var stone = MaterialAsset("Stone", new Color(0.48f, 0.50f, 0.45f));
        var rock = MaterialAsset("Rock", new Color(0.35f, 0.39f, 0.35f));
        var dark = MaterialAsset("CaveInterior", new Color(0.035f, 0.041f, 0.032f));
        var bark = MaterialAsset("Bark", new Color(0.25f, 0.22f, 0.16f));
        var foliage = MaterialAsset("Foliage", new Color(0.19f, 0.29f, 0.13f));
        var grass = MaterialAsset("GrassBlades", new Color(0.32f, 0.42f, 0.20f));

        var floorMesh = GridMesh();
        AssetDatabase.CreateAsset(floorMesh, Folder + "/GroundMesh.asset");
        var ground = MeshObject("ClearingGround", root.transform, floorMesh, groundMaterial);
        ground.AddComponent<MeshCollider>().sharedMesh = floorMesh;

        var slab = RingMesh("StoneSlab", new[] {0.0f, 0.055f}, new[] {0.50f, 0.46f}, 4, 0.13f);
        AssetDatabase.CreateAsset(slab, Folder + "/SlabMesh.asset");
        var stones = new GameObject("OldPaving").transform;
        stones.SetParent(root.transform, false);
        for (int i = 0; i < 80; i++)
        {
            float z = Range(random, -9f, 13.2f);
            float path = Mathf.Sin(z * 0.16f) * 2f + z * 0.15f;
            float x = path + Range(random, -2.9f, 2.9f);
            if (i < 24) { z = 10f + (i / 6) * 0.75f; x = 1.8f + (i % 6) * 0.7f; }
            var item = MeshObject("Stone_" + i, stones, slab, stone);
            item.transform.localPosition = new Vector3(x, -0.012f, z);
            item.transform.localRotation = Quaternion.Euler(0, Range(random, -28, 28), 0);
            item.transform.localScale = new Vector3(Range(random, 0.8f, 1.5f), 1, Range(random, 0.65f, 1.2f));
        }

        var entrance = new GameObject("CaveEntranceAnchor").transform;
        entrance.SetParent(root.transform, false);
        entrance.localPosition = new Vector3(4f, 0, 14f);
        var rockMesh = RingMesh("FacetedRock", new[] {0f, 0.35f, 0.85f, 1.1f}, new[] {0.7f, 1f, 0.75f, 0.25f}, 7, 0.18f);
        AssetDatabase.CreateAsset(rockMesh, Folder + "/RockMesh.asset");
        for (int i = 0; i < 10; i++)
        {
            float angle = Mathf.PI * i / 9f;
            var boulder = MeshObject("EntranceRock_" + i, entrance, rockMesh, rock);
            boulder.transform.localPosition = new Vector3(Mathf.Cos(angle) * 3.6f, Mathf.Sin(angle) * 3.7f, 1.25f);
            boulder.transform.localRotation = Quaternion.Euler(Range(random, -12, 12), Range(random, 0, 360), Range(random, -12, 12));
            boulder.transform.localScale = new Vector3(2.6f, 1.7f, 2.9f);
        }
        var interior = Primitive("CaveRecess", PrimitiveType.Cube, entrance, dark);
        interior.transform.localPosition = new Vector3(0, 1.8f, 2.45f);
        interior.transform.localScale = new Vector3(5.4f, 3.6f, 0.3f);

        var trunkMesh = RingMesh("Trunk", new[] {0f, 3.5f}, new[] {0.35f, 0.22f}, 7, 0.1f);
        var crownMesh = RingMesh("Canopy", new[] {0f, 0.6f, 1.5f, 2.6f}, new[] {0.9f, 1.6f, 1.2f, 0.1f}, 8, 0.12f);
        AssetDatabase.CreateAsset(trunkMesh, Folder + "/TrunkMesh.asset");
        AssetDatabase.CreateAsset(crownMesh, Folder + "/CanopyMesh.asset");
        var trees = new GameObject("ForestSilhouettes").transform;
        trees.SetParent(root.transform, false);
        for (int i = 0; i < 38; i++)
        {
            float angle = i * Mathf.PI * 2f / 38f + Range(random, -0.055f, 0.055f);
            float x = Mathf.Cos(angle) * Range(random, 23, 31);
            float z = Mathf.Sin(angle) * Range(random, 24, 30) + 2;
            if (z < -10 && Mathf.Abs(x) < 18) continue;
            if (z > 15 && Mathf.Abs(x - 4) < 6) continue;
            var tree = new GameObject("Tree_" + i).transform;
            tree.SetParent(trees, false);
            tree.localPosition = new Vector3(x, 0, z);
            float size = Range(random, 0.85f, 1.3f);
            tree.localScale = new Vector3(size, size, size);
            MeshObject("Trunk", tree, trunkMesh, bark);
            var canopy = MeshObject("Canopy", tree, crownMesh, foliage);
            canopy.transform.localPosition = new Vector3(0, 2.5f, 0);
            canopy.transform.localScale = new Vector3(1.7f, 1.45f, 1.7f);
        }

        var blades = GrassMesh(random);
        AssetDatabase.CreateAsset(blades, Folder + "/GrassMesh.asset");
        MeshObject("EdgeGrass", root.transform, blades, grass);
        var marker = bootstrap.gameObject.AddComponent<HomeClearingEnvironment>();
        marker.Configure(root, ground, entrance);
        ApplyCaveCollision();
        if (bootstrap.sceneCamera != null) bootstrap.sceneCamera.fieldOfView = 50f;
        SetLighting(false);
        AssetDatabase.SaveAssets();
        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene);
        Selection.activeGameObject = root;
        Debug.Log("[HomeClearing] Saved ground, old paving, cave silhouette and soft directional lighting.");
    }

    [MenuItem("Tools/Home Clearing/Lighting/Neutral Daylight")]
    public static void Neutral() { SetLighting(true); }

    [MenuItem("Tools/Home Clearing/Lighting/Soft Afternoon")]
    public static void Afternoon() { SetLighting(false); }

    [MenuItem("Tools/Home Clearing/Apply Cave Collision")]
    public static void ApplyCaveCollision()
    {
        var scene = SceneManager.GetActiveScene();
        if (EditorApplication.isPlaying || scene.path != HomePath)
            throw new InvalidOperationException("Open HomeScene outside Play Mode to apply collision.");
        var marker = UnityEngine.Object.FindObjectOfType<HomeClearingEnvironment>();
        if (marker == null || marker.EnvironmentRoot == null || marker.gameObject.scene != scene)
            throw new InvalidOperationException("Home clearing references are missing.");
        foreach (var mesh in marker.EnvironmentRoot.GetComponentsInChildren<MeshFilter>())
        {
            if (mesh.name.StartsWith("EntranceRock_", StringComparison.Ordinal) || mesh.name == "Trunk")
            {
                var collider = mesh.GetComponent<MeshCollider>();
                if (collider == null) collider = mesh.gameObject.AddComponent<MeshCollider>();
                collider.sharedMesh = mesh.sharedMesh;
            }
            else if (mesh.name == "CaveRecess" && mesh.GetComponent<Collider>() == null)
                mesh.gameObject.AddComponent<BoxCollider>();
        }
        EditorSceneManager.MarkSceneDirty(scene);
    }

    public static void SetLighting(bool neutral)
    {
        if (SceneManager.GetActiveScene().path != HomePath)
            throw new InvalidOperationException("Lighting preset is restricted to HomeScene.");
        foreach (var light in UnityEngine.Object.FindObjectsOfType<Light>())
        {
            if (light.gameObject.scene.path != HomePath || light.type != LightType.Directional) continue;
            light.transform.rotation = Quaternion.Euler(neutral ? 58 : 39, -38, 0);
            light.color = neutral ? new Color(1f, 0.99f, 0.96f) : new Color(1f, 0.95f, 0.85f);
            light.intensity = neutral ? 1f : 0.95f;
            light.shadows = LightShadows.Soft;
            light.shadowStrength = 0.72f;
            light.shadowBias = 0.035f;
            light.shadowNormalBias = 0.25f;
        }
        RenderSettings.ambientMode = AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = new Color(0.48f, 0.53f, 0.59f);
        RenderSettings.ambientEquatorColor = new Color(0.36f, 0.39f, 0.34f);
        RenderSettings.ambientGroundColor = new Color(0.22f, 0.24f, 0.18f);
        RenderSettings.fog = false;
        if (!EditorApplication.isPlaying)
            EditorSceneManager.MarkSceneDirty(SceneManager.GetActiveScene());
    }

    private static Material MaterialAsset(string name, Color color)
    {
        var material = new Material(Shader.Find("Standard")) { name = name, color = color };
        material.SetFloat("_Glossiness", 0.06f);
        material.SetFloat("_Metallic", 0);
        AssetDatabase.CreateAsset(material, Folder + "/" + name + ".mat");
        return material;
    }

    private static GameObject MeshObject(string name, Transform parent, Mesh mesh, Material material)
    {
        var item = new GameObject(name);
        item.transform.SetParent(parent, false);
        item.AddComponent<MeshFilter>().sharedMesh = mesh;
        item.AddComponent<MeshRenderer>().sharedMaterial = material;
        return item;
    }

    private static GameObject Primitive(string name, PrimitiveType type, Transform parent, Material material)
    {
        var item = GameObject.CreatePrimitive(type);
        item.name = name;
        item.transform.SetParent(parent, false);
        UnityEngine.Object.DestroyImmediate(item.GetComponent<Collider>());
        item.GetComponent<Renderer>().sharedMaterial = material;
        return item;
    }

    private static Mesh GridMesh()
    {
        const int count = 60;
        var vertices = new Vector3[(count + 1) * (count + 1)];
        var uv = new Vector2[vertices.Length];
        var triangles = new int[count * count * 6];
        for (int z = 0; z <= count; z++)
        for (int x = 0; x <= count; x++)
        {
            int i = z * (count + 1) + x;
            vertices[i] = new Vector3(x * 4f - count * 2f, 0, z * 4f - count * 2f);
            uv[i] = new Vector2(x / (float)count, z / (float)count);
            if (x == count || z == count) continue;
            int t = (z * count + x) * 6;
            triangles[t] = i; triangles[t + 1] = i + count + 1; triangles[t + 2] = i + 1;
            triangles[t + 3] = i + 1; triangles[t + 4] = i + count + 1; triangles[t + 5] = i + count + 2;
        }
        return MakeMesh("ClearingGround", vertices, triangles, uv);
    }

    private static Mesh RingMesh(string name, float[] heights, float[] radii, int sides, float irregularity)
    {
        var vertices = new List<Vector3>();
        var triangles = new List<int>();
        for (int level = 0; level < heights.Length - 1; level++)
        for (int side = 0; side < sides; side++)
        {
            Vector3 a = RingPoint(level, side, heights, radii, sides, irregularity);
            Vector3 b = RingPoint(level + 1, side, heights, radii, sides, irregularity);
            Vector3 c = RingPoint(level + 1, side + 1, heights, radii, sides, irregularity);
            Vector3 d = RingPoint(level, side + 1, heights, radii, sides, irregularity);
            AddTriangle(vertices, triangles, a, b, c);
            AddTriangle(vertices, triangles, a, c, d);
        }
        int last = heights.Length - 1;
        for (int side = 0; side < sides; side++)
        {
            AddTriangle(vertices, triangles, new Vector3(0, heights[last], 0),
                RingPoint(last, side + 1, heights, radii, sides, irregularity),
                RingPoint(last, side, heights, radii, sides, irregularity));
        }
        return MakeMesh(name, vertices.ToArray(), triangles.ToArray(), null);
    }

    private static Vector3 RingPoint(int level, int side, float[] heights, float[] radii, int sides, float irregularity)
    {
        side %= sides;
        float angle = side * Mathf.PI * 2f / sides;
        float radius = radii[level] * (1 + Mathf.Sin(side * 5.7f + level * 1.3f) * irregularity);
        return new Vector3(Mathf.Cos(angle) * radius, heights[level], Mathf.Sin(angle) * radius);
    }

    private static Mesh GrassMesh(System.Random random)
    {
        var vertices = new List<Vector3>();
        var triangles = new List<int>();
        for (int i = 0; i < 1700; i++)
        {
            float x = Range(random, -27, 27), z = Range(random, -25, 28);
            float edge = new Vector2(x / 16f, (z - 1) / 18f).magnitude;
            if (edge < 0.86f || edge > 1.48f) continue;
            float path = Mathf.Sin(z * 0.16f) * 2f + z * 0.15f;
            if (Mathf.Abs(x - path) < 3f) continue;
            var center = new Vector3(x, 0.012f, z);
            for (int blade = 0; blade < 5; blade++)
            {
                var offset = new Vector3(Range(random, -0.2f, 0.2f), 0, Range(random, -0.2f, 0.2f));
                float height = Range(random, 0.18f, 0.52f);
                var a = center + offset + Vector3.left * 0.045f;
                var b = center + offset + Vector3.right * 0.045f;
                var c = center + offset + new Vector3(0.10f, height, 0.05f);
                AddTriangle(vertices, triangles, a, b, c);
                AddTriangle(vertices, triangles, c, b, a);
            }
        }
        return MakeMesh("EdgeGrass", vertices.ToArray(), triangles.ToArray(), null);
    }

    private static void AddTriangle(List<Vector3> vertices, List<int> triangles, Vector3 a, Vector3 b, Vector3 c)
    {
        int start = vertices.Count;
        vertices.Add(a); vertices.Add(b); vertices.Add(c);
        triangles.Add(start); triangles.Add(start + 1); triangles.Add(start + 2);
    }

    private static Mesh MakeMesh(string name, Vector3[] vertices, int[] triangles, Vector2[] uv)
    {
        var mesh = new Mesh { name = name };
        if (vertices.Length > 65535) mesh.indexFormat = IndexFormat.UInt32;
        mesh.vertices = vertices;
        mesh.triangles = triangles;
        if (uv != null) mesh.uv = uv;
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();
        return mesh;
    }

    private static float Range(System.Random random, float min, float max)
    {
        return min + (float)random.NextDouble() * (max - min);
    }
}
