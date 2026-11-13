using UnityEngine;

[DisallowMultipleComponent]
public sealed class HomeClearingEnvironment : MonoBehaviour
{
    [SerializeField] private GameObject environmentRoot;
    [SerializeField] private GameObject ground;
    [SerializeField] private Transform entrance;

    public GameObject Ground { get { return ground; } }
    public Transform Entrance { get { return entrance; } }
    public GameObject EnvironmentRoot { get { return environmentRoot; } }

    public bool IsValid(float playBounds, float triggerRadius)
    {
        if (!isActiveAndEnabled || environmentRoot == null || ground == null || entrance == null)
            return false;
        if (!environmentRoot.activeInHierarchy || !ground.activeInHierarchy || !entrance.gameObject.activeInHierarchy)
            return false;
        if (environmentRoot.scene != gameObject.scene || !ground.transform.IsChildOf(environmentRoot.transform) ||
            !entrance.IsChildOf(environmentRoot.transform))
            return false;
        var collider = ground.GetComponent<Collider>();
        var renderer = ground.GetComponent<Renderer>();
        if (collider == null || !collider.enabled || collider.isTrigger || renderer == null || !renderer.enabled)
            return false;
        var bounds = collider.bounds;
        if (bounds.min.x > -playBounds || bounds.max.x < playBounds ||
            bounds.min.z > -playBounds || bounds.max.z < playBounds || Mathf.Abs(bounds.max.y) > 0.02f)
            return false;
        var point = entrance.position;
        return Mathf.Abs(point.y) < 0.1f && Mathf.Abs(point.x) < playBounds - 1 &&
            Mathf.Abs(point.z) < playBounds - 1 && point.sqrMagnitude > (triggerRadius + 1) * (triggerRadius + 1);
    }

    public void Configure(GameObject root, GameObject groundObject, Transform entranceTransform)
    {
        environmentRoot = root;
        ground = groundObject;
        entrance = entranceTransform;
    }
}
