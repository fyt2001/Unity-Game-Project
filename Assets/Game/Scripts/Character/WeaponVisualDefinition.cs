using UnityEngine;

/// <summary>Art contract for a rigid weapon. Gameplay stats remain in Lua.</summary>
[CreateAssetMenu(menuName = "Game/Weapon Visual Definition")]
public sealed class WeaponVisualDefinition : ScriptableObject
{
    public GameObject prefab;
    public string handBone = "Fist.R";
    public Vector3 gripPosition;
    public Vector3 gripRotation;
    public float worldScale = 1f;
    public string holdState;
    public string attackState;
    public AnimationClip attackClip;
    [Range(0f, 1f)] public float releaseFraction = 0.25f;
    [Range(0.5f, 3f)] public float maximumAnimationSpeed = 2f;
    public float trailDuration = 0.18f;
}
