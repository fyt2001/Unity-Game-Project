using UnityEngine;

/// <summary>Physical attachment and attack presentation; never deals damage.</summary>
public sealed class CharacterWeaponView : MonoBehaviour
{
    public GameObject EquippedWeapon { get; private set; }
    public Transform HandSocket { get; private set; }
    public int EquippedPattern { get; private set; }
    public float LastReleaseDelay { get; private set; }
    private GameObject model;
    private Animator animator;
    private Transform visualRoot;
    private WeaponVisualDefinition sword, pistol, definition;
    private Transform muzzle;
    private GameObject muzzleFlash;
    private TrailRenderer bladeTrail;
    private int combatLayer = -1;
    private float attackRemaining, effectRemaining, aimRemaining;
    private Vector3 direction;
    private Vector3 gripRestPosition;
    private bool paused;
    private float animatorSpeedBeforePause = 1f;
    private bool fastAttack;

    public void Initialize(GameObject modelInstance, Animator characterAnimator, Transform root,
        WeaponVisualDefinition swordDefinition, WeaponVisualDefinition pistolDefinition)
    {
        model = modelInstance; animator = characterAnimator; visualRoot = root;
        sword = swordDefinition; pistol = pistolDefinition;
        combatLayer = animator ? animator.GetLayerIndex("CombatUpper") : -1;
    }

    public bool Equip(int pattern)
    {
        if (pattern == EquippedPattern && EquippedWeapon) return true;
        Clear();
        var next = pattern == 1 ? sword : pattern == 2 ? pistol : null;
        if (animator && combatLayer < 0) combatLayer = animator.GetLayerIndex("CombatUpper");
        if (!model || !next || !next.prefab || combatLayer < 0) return false;
        Transform hand = null;
        foreach (var bone in model.GetComponentsInChildren<Transform>(true))
            if (bone.name == next.handBone) { hand = bone; break; }
        if (!hand) { Debug.LogWarning("[CharacterWeaponView] Missing hand bone: " + next.handBone); return false; }
        HandSocket = new GameObject("Socket_Hand_R").transform;
        HandSocket.SetParent(hand, false);
        EquippedWeapon = Instantiate(next.prefab, HandSocket, false);
        EquippedWeapon.name = next.prefab.name;
        var weapon = EquippedWeapon.transform;
        weapon.localPosition = next.gripPosition;
        weapon.localRotation = Quaternion.Euler(next.gripRotation);
        var scale = hand.lossyScale;
        weapon.localScale = new Vector3(next.worldScale / Mathf.Max(Mathf.Abs(scale.x), 0.0001f),
            next.worldScale / Mathf.Max(Mathf.Abs(scale.y), 0.0001f),
            next.worldScale / Mathf.Max(Mathf.Abs(scale.z), 0.0001f));
        foreach (var child in EquippedWeapon.GetComponentsInChildren<Transform>(true))
        {
            child.gameObject.layer = gameObject.layer;
            if (child.name == "Muzzle") muzzle = child;
            if (child.name == "MuzzleFlash") muzzleFlash = child.gameObject;
        }
        if (muzzleFlash) muzzleFlash.SetActive(false);
        bladeTrail = EquippedWeapon.GetComponentInChildren<TrailRenderer>(true);
        if (bladeTrail) { bladeTrail.emitting = false; bladeTrail.Clear(); }
        definition = next; EquippedPattern = pattern;
        gripRestPosition = weapon.localPosition;
        animator.SetLayerWeight(combatLayer, 1f);
        Hold();
        return true;
    }

    public float Begin(int pattern, float dx, float dy, float interval)
    {
        if (!Equip(pattern) || !definition.attackClip) return 0f;
        direction = new Vector3(dx, 0f, dy);
        if (direction.sqrMagnitude > 0.0001f) direction.Normalize();
        else direction = visualRoot.forward;
        aimRemaining = Mathf.Max(0.15f, interval);
        // Fast shots use the firing pose already in progress instead of restarting it.
        float speed = Mathf.Clamp(definition.attackClip.length / Mathf.Max(interval, 0.15f),
            1f, definition.maximumAnimationSpeed);
        float naturalDelay = definition.attackClip.length * definition.releaseFraction / speed;
        LastReleaseDelay = Mathf.Min(naturalDelay, Mathf.Max(0.01f, interval * 0.4f));
        fastAttack = LastReleaseDelay < naturalDelay - 0.0001f;
        // At the speed cap trim the windup, rather than releasing before the swing pose.
        float startPhase = Mathf.Max(0f, definition.releaseFraction - LastReleaseDelay * speed / definition.attackClip.length);
        if (attackRemaining <= 0f || pattern == 1)
        {
            animator.SetFloat("CombatSpeed", speed);
            animator.Play(definition.attackState, combatLayer, startPhase);
            attackRemaining = definition.attackClip.length * (1f - startPhase) / speed;
        }
        // Ensure a valid hand/muzzle pose even when Lua fires before Animator's next update.
        animator.Update(0f);
        ApplyAim();
        return LastReleaseDelay;
    }

    public void Release(int pattern)
    {
        if (!EquippedWeapon || pattern != EquippedPattern) return;
        // Lua can catch up multiple attacks in one frame. Sample the configured release
        // pose for fast attacks so flash/trail always accompanies an actual firing/swing pose.
        if (animator && definition.attackClip)
        {
            var state = animator.GetCurrentAnimatorStateInfo(combatLayer);
            if (fastAttack || !state.IsName(definition.attackState) || state.normalizedTime < definition.releaseFraction)
            {
                animator.Play(definition.attackState, combatLayer, definition.releaseFraction);
                animator.Update(0f);
            }
        }
        effectRemaining = pattern == 1 ? definition.trailDuration : 0.065f;
        if (bladeTrail) bladeTrail.emitting = true;
        if (muzzleFlash) muzzleFlash.SetActive(true);
    }

    public Vector3 MuzzlePosition()
    {
        if (animator) animator.Update(0f);
        ApplyAim();
        return muzzle ? muzzle.position : transform.position;
    }

    private void Hold()
    {
        if (!animator || combatLayer < 0 || !definition) return;
        animator.CrossFade(definition.holdState, 0.07f, combatLayer);
    }

    private void Update()
    {
        if (paused) return;
        float dt = Time.deltaTime;
        if (attackRemaining > 0f)
        {
            attackRemaining -= dt;
            if (attackRemaining <= 0f) Hold();
        }
        if (effectRemaining > 0f)
        {
            effectRemaining -= dt;
            if (EquippedPattern == 2 && EquippedWeapon)
                EquippedWeapon.transform.localPosition = gripRestPosition +
                    EquippedWeapon.transform.localRotation * Vector3.back * (0.02f * effectRemaining / 0.065f);
            if (effectRemaining <= 0f)
            {
                if (muzzleFlash) muzzleFlash.SetActive(false);
                if (bladeTrail) bladeTrail.emitting = false;
                if (EquippedWeapon) EquippedWeapon.transform.localPosition = gripRestPosition;
            }
        }
        float previousAim = aimRemaining;
        aimRemaining = Mathf.Max(0f, aimRemaining - dt);
        if (previousAim > 0f && aimRemaining == 0f && visualRoot)
            visualRoot.localRotation = Quaternion.identity;
    }

    private void ApplyAim()
    {
        if (!visualRoot || aimRemaining <= 0f || direction.sqrMagnitude < 0.0001f) return;
        visualRoot.rotation = Quaternion.LookRotation(direction, Vector3.up);
    }

    private void LateUpdate() { ApplyAim(); }

    public void SetPaused(bool value)
    {
        if (paused == value) return;
        paused = value;
        if (!animator) return;
        if (value) { animatorSpeedBeforePause = animator.speed; animator.speed = 0f; }
        else animator.speed = animatorSpeedBeforePause;
    }

    public void Clear()
    {
        SetPaused(false);
        if (animator && combatLayer >= 0) animator.SetLayerWeight(combatLayer, 0f);
        if (HandSocket) { HandSocket.gameObject.SetActive(false); Destroy(HandSocket.gameObject); }
        else if (EquippedWeapon) { EquippedWeapon.SetActive(false); Destroy(EquippedWeapon); }
        EquippedWeapon = null; HandSocket = null; muzzle = null; muzzleFlash = null; bladeTrail = null;
        definition = null; EquippedPattern = 0; LastReleaseDelay = 0f;
        attackRemaining = effectRemaining = aimRemaining = 0f;
        if (visualRoot) visualRoot.localRotation = Quaternion.identity;
    }

    private void OnDisable() { Clear(); }
}
