using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;
using UnityEditor.SceneManagement;

public static class HomeDesertArtBuilder
{
    const string Folder="Assets/Game/Resources/DesertOasis/";
    [MenuItem("Tools/Home Clearing/Apply Painted Desert Art")]
    public static void Apply()
    {
        var scene=UnityEngine.SceneManagement.SceneManager.GetActiveScene();
        if(EditorApplication.isPlaying || scene.path!="Assets/Scenes/HomeScene.unity" || scene.isDirty)
            throw new InvalidOperationException("Open a saved HomeScene outside Play before applying art.");
        var marker=UnityEngine.Object.FindObjectOfType<HomeClearingEnvironment>();
        if(!marker || !marker.IsValid(22,2.5f)) throw new Exception("Existing clearing references are invalid.");
        if(GameObject.Find("DesertOasisArt")) throw new Exception("Desert art already exists; review before applying again.");
        var texture=AssetDatabase.LoadAssetAtPath<Texture2D>(Folder+"PaintedSand.png");
        var bones=AssetDatabase.LoadAssetAtPath<GameObject>(Folder+"AncientRibcage.fbx");
        if(!texture || !bones) throw new Exception("Painted texture and Blender skeleton must be imported first.");
        var importer=(TextureImporter)AssetImporter.GetAtPath(Folder+"PaintedSand.png");
        importer.wrapMode=TextureWrapMode.Repeat;importer.maxTextureSize=2048;importer.mipmapEnabled=true;importer.SaveAndReimport();
        var sand=Mat("PaintedSand","Game/DesertOasis/PaintedSand",new Color(.87f,.83f,.76f));sand.mainTexture=texture;
        marker.Ground.GetComponent<Renderer>().sharedMaterial=sand;
        var bark=Mat("WeatheredWood","Game/DesertOasis/IllustratedBone",new Color(.46f,.33f,.22f));
        var grass=Mat("DryGrass","Standard",new Color(.56f,.49f,.29f));
        var stone=Mat("Sandstone","Game/DesertOasis/IllustratedBone",new Color(.63f,.49f,.35f));
        foreach(var r in marker.EnvironmentRoot.GetComponentsInChildren<Renderer>())
        {
            if(r.name=="Canopy") r.enabled=false;
            else if(r.name=="Trunk") r.sharedMaterial=bark;
            else if(r.name=="EdgeGrass") r.sharedMaterial=grass;
            else if(r.name.StartsWith("Stone_")) r.enabled=false;
            else if(r.name.StartsWith("EntranceRock_")) r.sharedMaterial=stone;
        }
        var root=new GameObject("DesertOasisArt");root.transform.SetParent(marker.EnvironmentRoot.transform,false);
        var dryTreeMesh=HomeDesertAtmosphere.CreateDryTreeMesh();AssetDatabase.CreateAsset(dryTreeMesh,Folder+"DryTreeMesh.asset");
        foreach(var trunkRenderer in marker.EnvironmentRoot.GetComponentsInChildren<Renderer>()) if(trunkRenderer.name=="Trunk"){
            var trunk=trunkRenderer.transform;trunkRenderer.enabled=false;var tree=new GameObject("WeatheredBranches");tree.transform.SetParent(root.transform,false);tree.transform.position=trunk.position;tree.transform.rotation=trunk.rotation;tree.transform.localScale=trunk.lossyScale;tree.AddComponent<MeshFilter>().sharedMesh=dryTreeMesh;tree.AddComponent<MeshRenderer>().sharedMaterial=bark;
        }
        var boneMaterial=Mat("IllustratedBone","Game/DesertOasis/IllustratedBone",new Color(.78f,.66f,.49f));
        for(int i=0;i<2;i++)
        {
            var item=UnityEngine.Object.Instantiate(bones,root.transform,false);item.name="AncientRibs_"+i;
            // FBX conversion preserves its axis transform; rotate only about world up.
            item.transform.localPosition=i==0?new Vector3(-14,-.10f,6):new Vector3(13,-.07f,-5);
            item.transform.localRotation=Quaternion.Euler(0,i==0?-28:38,0)*item.transform.localRotation;
            item.transform.localScale*=i==0?1.15f:.8f;
            foreach(var r in item.GetComponentsInChildren<Renderer>())r.sharedMaterial=boneMaterial;
        }
        var pond=new GameObject("ShallowOasis");pond.transform.SetParent(root.transform,false);pond.transform.localPosition=new Vector3(-8,.018f,4);
        var mesh=PondMesh();AssetDatabase.CreateAsset(mesh,Folder+"OasisMesh.asset");
        pond.AddComponent<MeshFilter>().sharedMesh=mesh;
        var pr=pond.AddComponent<MeshRenderer>();pr.sharedMaterial=Mat("ShallowWater","Game/DesertOasis/ShallowWater",new Color(.36f,.53f,.48f,.65f));
        pr.shadowCastingMode=ShadowCastingMode.Off;pr.receiveShadows=false;
        var dust=new GameObject("WindborneSand");dust.transform.SetParent(root.transform,false);dust.transform.localPosition=new Vector3(0,1.5f,0);
        var ps=dust.AddComponent<ParticleSystem>();ps.Stop(true,ParticleSystemStopBehavior.StopEmittingAndClear);var main=ps.main;main.playOnAwake=true;main.loop=true;main.duration=12;main.startLifetime=12;
        main.startSpeed=.18f;main.startSize=new ParticleSystem.MinMaxCurve(.04f,.12f);main.startColor=new Color(.91f,.80f,.59f,.18f);main.maxParticles=96;main.simulationSpace=ParticleSystemSimulationSpace.World;
        var emission=ps.emission;emission.rateOverTime=6;var shape=ps.shape;shape.shapeType=ParticleSystemShapeType.Box;shape.scale=new Vector3(46,2,46);
        var velocity=ps.velocityOverLifetime;velocity.enabled=true;velocity.space=ParticleSystemSimulationSpace.World;velocity.x=.15f;velocity.z=.06f;
        var fade=ps.colorOverLifetime;fade.enabled=true;var gradient=new Gradient();gradient.SetKeys(new[]{new GradientColorKey(Color.white,0),new GradientColorKey(Color.white,1)},new[]{new GradientAlphaKey(0,0),new GradientAlphaKey(1,.25f),new GradientAlphaKey(1,.75f),new GradientAlphaKey(0,1)});fade.color=gradient;
        ps.GetComponent<ParticleSystemRenderer>().sharedMaterial=Mat("Dust","Game/DesertOasis/Dust",Color.white);ps.Play();
        RenderSettings.ambientMode=AmbientMode.Trilight;RenderSettings.ambientSkyColor=new Color(.66f,.63f,.57f);RenderSettings.ambientEquatorColor=new Color(.52f,.48f,.40f);RenderSettings.ambientGroundColor=new Color(.34f,.29f,.23f);
        RenderSettings.fog=true;RenderSettings.fogMode=FogMode.Linear;RenderSettings.fogColor=new Color(.72f,.62f,.48f);RenderSettings.fogStartDistance=36;RenderSettings.fogEndDistance=115;
        foreach(var light in UnityEngine.Object.FindObjectsOfType<Light>())if(light.type==LightType.Directional && light.gameObject.scene==scene){light.color=new Color(1,.96f,.88f);light.intensity=.95f;light.shadows=LightShadows.Soft;light.shadowStrength=.32f;}
        AssetDatabase.SaveAssets();EditorSceneManager.MarkSceneDirty(scene);EditorSceneManager.SaveScene(scene);
    }
    static Material Mat(string name,string shaderName,Color color)
    {
        var shader=Shader.Find(shaderName);if(!shader)throw new Exception("Shader missing: "+shaderName);
        var mat=new Material(shader){name=name};if(mat.HasProperty("_Color"))mat.color=color;if(mat.HasProperty("_Glossiness"))mat.SetFloat("_Glossiness",.08f);
        AssetDatabase.CreateAsset(mat,Folder+name+".mat");return mat;
    }
    static Mesh PondMesh()
    {
        const int count=64;var vertices=new Vector3[1+count*2];var colors=new Color[vertices.Length];var triangles=new List<int>();colors[0]=Color.white;
        for(int i=0;i<count;i++)
        {
            float angle=i*Mathf.PI*2/count;float radius=1+.06f*Mathf.Sin(angle*5)+.04f*Mathf.Sin(angle*9);
            var edge=new Vector3(Mathf.Cos(angle)*6.2f*radius,0,Mathf.Sin(angle)*3.8f*radius);
            vertices[1+i]=edge*.87f;colors[1+i]=Color.white;vertices[1+count+i]=edge;colors[1+count+i]=new Color(1,1,1,0);
            int next=(i+1)%count;triangles.AddRange(new[]{0,1+next,1+i,1+i,1+next,1+count+i,1+next,1+count+next,1+count+i});
        }
        var mesh=new Mesh{name="Shallow Oasis"};mesh.vertices=vertices;mesh.colors=colors;mesh.triangles=triangles.ToArray();mesh.RecalculateNormals();mesh.RecalculateBounds();return mesh;
    }
}
