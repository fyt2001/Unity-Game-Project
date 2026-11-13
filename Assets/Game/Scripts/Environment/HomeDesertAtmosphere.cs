using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;



[DefaultExecutionOrder(-100)]
[DisallowMultipleComponent]
public sealed class HomeDesertAtmosphere : MonoBehaviour
{
    void Start() {
        var marker=GetComponent<HomeClearingEnvironment>();
        if(!marker) { Debug.LogWarning("[DesertOasis] Home environment component is missing."); return; }
        Physics.SyncTransforms();
        if(!marker.IsValid(22,2.5f)) { Debug.LogWarning("[DesertOasis] Home environment is not ready."); return; }
        if(marker.EnvironmentRoot.transform.Find("DesertOasisArt")) return;
        var texture=Resources.Load<Texture2D>("DesertOasis/PaintedSand");
        var bones=Resources.Load<GameObject>("DesertOasis/AncientRibcage");
        if(!texture || !bones) { Debug.LogError("[DesertOasis] Art resources are missing."); return; }
        foreach(var shaderName in new[]{"Game/DesertOasis/PaintedSand","Game/DesertOasis/IllustratedBone","Game/DesertOasis/ShallowWater","Game/DesertOasis/Dust","Standard"}) if(!Shader.Find(shaderName)){Debug.LogError("[DesertOasis] Required shader missing: "+shaderName);return;}
        texture.wrapMode=TextureWrapMode.Repeat;
        foreach(var renderer in marker.EnvironmentRoot.GetComponentsInChildren<Renderer>(true)) original.Add(new RendererState{renderer=renderer,materials=renderer.sharedMaterials,enabled=renderer.enabled});
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
        var root=new GameObject("DesertOasisArt");artRoot=root;root.transform.SetParent(marker.EnvironmentRoot.transform,false);
        var dryTreeMesh=CreateDryTreeMesh();owned.Add(dryTreeMesh);
        foreach(var state in original) if(state.renderer && state.renderer.name=="Trunk"){
            var trunk=state.renderer.transform;state.renderer.enabled=false;
            var tree=new GameObject("WeatheredBranches");tree.transform.SetParent(root.transform,false);
            tree.transform.position=trunk.position;tree.transform.rotation=trunk.rotation;tree.transform.localScale=trunk.lossyScale;
            tree.AddComponent<MeshFilter>().sharedMesh=dryTreeMesh;tree.AddComponent<MeshRenderer>().sharedMaterial=bark;
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
        var mesh=PondMesh();owned.Add(mesh);
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
        previousAmbient=RenderSettings.ambientMode;previousSky=RenderSettings.ambientSkyColor;previousEquator=RenderSettings.ambientEquatorColor;previousGround=RenderSettings.ambientGroundColor;
        previousFog=RenderSettings.fog;previousFogMode=RenderSettings.fogMode;previousFogColor=RenderSettings.fogColor;previousFogStart=RenderSettings.fogStartDistance;previousFogEnd=RenderSettings.fogEndDistance;lightingApplied=true;
        RenderSettings.ambientMode=AmbientMode.Trilight;RenderSettings.ambientSkyColor=new Color(.66f,.63f,.57f);RenderSettings.ambientEquatorColor=new Color(.52f,.48f,.40f);RenderSettings.ambientGroundColor=new Color(.34f,.29f,.23f);
        RenderSettings.fog=true;RenderSettings.fogMode=FogMode.Linear;RenderSettings.fogColor=new Color(.72f,.62f,.48f);RenderSettings.fogStartDistance=36;RenderSettings.fogEndDistance=115;
        foreach(var light in UnityEngine.Object.FindObjectsOfType<Light>())if(light.type==LightType.Directional && light.gameObject.scene==gameObject.scene){originalLights.Add(new LightState{light=light,color=light.color,intensity=light.intensity,shadows=light.shadows,strength=light.shadowStrength});light.color=new Color(1,.96f,.88f);light.intensity=.95f;light.shadows=LightShadows.Soft;light.shadowStrength=.32f;}

    }
    readonly List<UnityEngine.Object> owned = new List<UnityEngine.Object>();
    sealed class RendererState { public Renderer renderer; public Material[] materials; public bool enabled; }
    readonly List<RendererState> original = new List<RendererState>();
    GameObject artRoot;
    sealed class LightState {public Light light;public Color color;public float intensity,strength;public LightShadows shadows;}
    readonly List<LightState> originalLights=new List<LightState>();
    bool lightingApplied,previousFog;FogMode previousFogMode;AmbientMode previousAmbient;
    Color previousSky,previousEquator,previousGround,previousFogColor;float previousFogStart,previousFogEnd;
    void OnDestroy(){
        foreach(var state in original) if(state.renderer){state.renderer.sharedMaterials=state.materials;state.renderer.enabled=state.enabled;}
        foreach(var state in originalLights) if(state.light){state.light.color=state.color;state.light.intensity=state.intensity;state.light.shadows=state.shadows;state.light.shadowStrength=state.strength;}
        if(lightingApplied && UnityEngine.SceneManagement.SceneManager.GetActiveScene()==gameObject.scene){RenderSettings.ambientMode=previousAmbient;RenderSettings.ambientSkyColor=previousSky;RenderSettings.ambientEquatorColor=previousEquator;RenderSettings.ambientGroundColor=previousGround;RenderSettings.fog=previousFog;RenderSettings.fogMode=previousFogMode;RenderSettings.fogColor=previousFogColor;RenderSettings.fogStartDistance=previousFogStart;RenderSettings.fogEndDistance=previousFogEnd;}
        if(artRoot) Destroy(artRoot);foreach(var asset in owned) if(asset) Destroy(asset);
    }
    Material Mat(string name,string shaderName,Color color)
    {
        var shader=Shader.Find(shaderName);if(!shader)throw new Exception("Shader missing: "+shaderName);
        var mat=new Material(shader){name=name};if(mat.HasProperty("_Color"))mat.color=color;if(mat.HasProperty("_Glossiness"))mat.SetFloat("_Glossiness",.08f);
        owned.Add(mat); return mat;
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
    public static Mesh CreateDryTreeMesh()
    {
        var vertices=new List<Vector3>();var triangles=new List<int>();
        var points=new[]{new Vector3(0,0,0),new Vector3(.08f,1.3f,0),new Vector3(-.12f,2.7f,.12f),new Vector3(.1f,3.25f,.15f),new Vector3(-.85f,2.1f,0),new Vector3(-1.2f,2.7f,.1f),new Vector3(.85f,2.5f,.2f),new Vector3(1.25f,2.85f,.3f),new Vector3(-.7f,3.1f,.6f)};
        var edges=new[]{0,1,1,2,2,3,1,4,4,5,2,6,6,7,2,8};
        for(int e=0;e<edges.Length;e+=2){var a=points[edges[e]];var b=points[edges[e+1]];var axis=(b-a).normalized;var side=Vector3.Cross(axis,Vector3.forward).normalized;var other=Vector3.Cross(axis,side);int start=vertices.Count;
            for(int end=0;end<2;end++){float radius=e==0?(end==0?.17f:.12f):(end==0?.10f:.035f);for(int i=0;i<8;i++){float angle=i*Mathf.PI/4;vertices.Add((end==0?a:b)+(side*Mathf.Cos(angle)+other*Mathf.Sin(angle))*radius);}}
            for(int i=0;i<8;i++){int n=(i+1)%8;triangles.AddRange(new[]{start+i,start+n,start+8+i,start+n,start+8+n,start+8+i});}
        }
        var mesh=new Mesh{name="Weathered Branches"};mesh.vertices=vertices.ToArray();mesh.triangles=triangles.ToArray();mesh.RecalculateNormals();mesh.RecalculateBounds();return mesh;
    }
}
