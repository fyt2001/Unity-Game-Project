using UnityEngine;
using System;
using System.Collections;
using UnityEngine.Networking;

public class WebRequestLua : MonoBehaviour {
    private static WebRequestLua s_instance;

    public static WebRequestLua Get() {
        return s_instance;
    }

    private void Awake() {
        s_instance = this;
    }

    public void Request(string url, Action<string> postCall) {
        StartCoroutine(GetUrl(url, postCall));
    }


    public IEnumerator GetUrl(string url, Action<string> postCall) {
        UnityWebRequest request = UnityWebRequest.Get(url);
        yield return request.SendWebRequest();
        if (request.isNetworkError || request.isHttpError) {
            postCall(request.error);
        }
        else {
            if (postCall != null) {
                postCall(request.downloadHandler.text);
            }
        }
    }
}