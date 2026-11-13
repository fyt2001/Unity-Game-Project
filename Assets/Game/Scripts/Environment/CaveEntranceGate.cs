using UnityEngine;

[DisallowMultipleComponent]
public sealed class CaveEntranceGate : MonoBehaviour
{
    private Transform player;
    private Interactable interaction;
    private BoxCollider volume;
    private Vector3 previousPosition;

    public void Configure(Transform playerTransform, Interactable target, BoxCollider triggerVolume)
    {
        player = playerTransform;
        interaction = target;
        volume = triggerVolume;
        previousPosition = player.position;
    }

    private void LateUpdate()
    {
        if (player == null || interaction == null || volume == null) return;
        Vector3 current = player.position;
        if (CrossedEntrance(previousPosition, current)) interaction.Interact();
        previousPosition = current;
    }

    public bool CrossedEntrance(Vector3 previous, Vector3 current)
    {
        if (volume == null || !volume.enabled || !volume.gameObject.activeInHierarchy) return false;
        Vector3 from = volume.transform.InverseTransformPoint(previous);
        Vector3 to = volume.transform.InverseTransformPoint(current);
        Vector3 half = volume.size * 0.5f;
        float threshold = volume.center.z - half.z;
        // Only an inward crossing through the front opening can start the dungeon.
        if (from.z >= threshold || to.z < threshold) return false;
        float t = (threshold - from.z) / (to.z - from.z);
        Vector3 crossing = Vector3.Lerp(from, to, t);
        return Mathf.Abs(crossing.x - volume.center.x) <= half.x &&
            crossing.y >= volume.center.y - half.y && crossing.y <= volume.center.y + half.y;
    }
}
