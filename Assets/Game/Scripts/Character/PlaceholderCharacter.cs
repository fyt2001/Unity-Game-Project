using UnityEngine;

/// <summary>
/// 兼容层：保留原组件名，逻辑已上移到 Model3DCharacterView（统一角色视图基类）。
/// 现在它就是一个 3D 角色视图——默认程序化占位体，挂上 modelPrefab 即替换为真实模型，
/// 并支持 Play(CharacterState) / SetFlip 统一接口，与项目 Spine 角色的封装约定对齐。
/// </summary>
public class PlaceholderCharacter : Model3DCharacterView { }
