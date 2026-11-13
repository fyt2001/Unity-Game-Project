using UnityEngine;

/// <summary>
/// Casual RPG VFX 资源包内「丢失脚本」的重建版。
///
/// 背景：导入的 Projectiles_*.prefab（frost / wind / water / magic）上挂着一个
/// MonoBehaviour，其脚本随资源包丢失（在原项目 ShaoNvClient 中同样缺失，只有
/// 预制体里的 guid 引用，没有对应 .cs），导致 Instantiate 时刷屏：
/// "The referenced script on this Behaviour (Game Object 'trail') is missing!"
///
/// 预制体里保留下来的序列化字段为 materialId / scrollSpeedX / scrollSpeedY，
/// 行为显然是「按速度滚动材质主贴图 UV」，让拖尾 / 能量条产生流动感。
/// 这里用同名同类型字段还原该行为；本文件 .meta 的 guid 被设为原脚本 guid
/// (993abc9b17d83a8488efa7d8aedd96d6)，使 4 个预制体的悬空引用重新解析。
/// Unity 按 guid 匹配脚本，与类名无关，所以类名可自定义。
///
/// 该脚本纯表现、无副作用：缺失时特效依然播放，只是贴图不再流动。
/// </summary>
public class CasualRPGVFX_UVScroller : MonoBehaviour
{
    public int materialId = 0;
    public float scrollSpeedX = 0f;
    public float scrollSpeedY = 0f;

    private Renderer _renderer;
    private Material _material;
    private Vector2 _offset;

    private void Awake()
    {
        _renderer = GetComponent<Renderer>();
        _material = ResolveMaterial();
    }

    private void OnEnable()
    {
        // 实例来自对象池，被复用时重新取一次（Renderer 可能已换）
        if (_renderer == null) _renderer = GetComponent<Renderer>();
        if (_material == null) _material = ResolveMaterial();
    }

    private Material ResolveMaterial()
    {
        if (_renderer == null) return null;

        if (materialId >= 0 && materialId < _renderer.materials.Length)
            return _renderer.materials[materialId];

        return _renderer.material;
    }

    private void Update()
    {
        if (_renderer == null || _material == null) return;
        if (scrollSpeedX == 0f && scrollSpeedY == 0f) return;

        _offset.x = (_offset.x + scrollSpeedX * Time.deltaTime) % 1f;
        _offset.y = (_offset.y + scrollSpeedY * Time.deltaTime) % 1f;
        _material.mainTextureOffset = _offset;
    }
}
