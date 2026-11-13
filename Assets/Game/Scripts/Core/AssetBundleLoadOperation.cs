// =============================================================================
// AssetBundleLoadOperation.cs - AssetBundle 异步加载操作封装（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 ThirdParty/AssetBundleManager/AssetBundleLoadOperation.cs
// 适配: 精简为 My project 所需的核心操作类型，移除 ODR/AppSlicing
// =============================================================================

using UnityEngine;
using UnityEngine.SceneManagement;
using System.Collections;
using UnityEngine.Networking;

namespace MyAssetBundles
{
    public abstract class AssetBundleLoadOperation : IEnumerator
    {
        public object Current { get { return null; } }

        public bool MoveNext() { return !IsDone(); }

        public void Reset() { }

        public abstract bool Update();

        public abstract bool IsDone();
    }

    public abstract class AssetBundleDownloadOperation : AssetBundleLoadOperation
    {
        private bool _done;

        public string AssetBundleName { get; private set; }
        public LoadedAssetBundle AssetBundle { get; protected set; }
        public string Error { get; protected set; }

        protected abstract bool DownloadIsDone { get; }
        protected abstract void FinishDownload();

        public override bool Update()
        {
            if (!_done && DownloadIsDone)
            {
                FinishDownload();
                _done = true;
            }
            return !_done;
        }

        public override bool IsDone() { return _done; }

        public abstract string GetSourceURL();

        protected AssetBundleDownloadOperation(string assetBundleName)
        {
            AssetBundleName = assetBundleName;
        }
    }

    public class AssetBundleDownloadFromFileOperation : AssetBundleDownloadOperation
    {
        private AssetBundleCreateRequest _request;
        private string _url;

        public AssetBundleDownloadFromFileOperation(string assetBundleName, AssetBundleCreateRequest request, string url)
            : base(assetBundleName)
        {
            _url = url;
            _request = request;
        }

        protected override bool DownloadIsDone
        {
            get { return _request == null || _request.isDone; }
        }

        protected override void FinishDownload()
        {
            AssetBundle bundle = _request == null ? null : _request.assetBundle;
            if (bundle == null)
            {
                Error = $"{AssetBundleName} is not a valid asset bundle.";
            }
            else
            {
                AssetBundle = new LoadedAssetBundle(bundle);
            }
            _request = null;
        }

        public override string GetSourceURL() { return _url; }
    }

    public class AssetBundleDownloadFromWebOperation : AssetBundleDownloadOperation
    {
        private UnityWebRequest request;
        private readonly string url;

        public AssetBundleDownloadFromWebOperation(string bundleName, string source)
            : base(bundleName)
        {
            url = source;
            request = UnityWebRequestAssetBundle.GetAssetBundle(source);
            request.timeout = 30;
            request.SendWebRequest();
        }

        protected override bool DownloadIsDone => request == null || request.isDone;

        protected override void FinishDownload()
        {
            try
            {
                if (request == null || request.result != UnityWebRequest.Result.Success)
                    Error = request == null ? "No download request." : (request.error ?? "AssetBundle download failed.");
                else
                {
                    var bundle = DownloadHandlerAssetBundle.GetContent(request);
                    if (bundle == null) Error = "Downloaded data is not an AssetBundle.";
                    else AssetBundle = new LoadedAssetBundle(bundle);
                }
            }
            catch (System.Exception e) { Error = e.Message; }
            finally
            {
                request?.Dispose();
                request = null;
            }
        }

        public override string GetSourceURL() => url;
    }

#if UNITY_EDITOR
    public class AssetBundleLoadLevelSimulationOperation : AssetBundleLoadOperation
    {
        private AsyncOperation _operation;

        public AssetBundleLoadLevelSimulationOperation(string assetBundleName, string levelName, bool isAdditive)
        {
            string[] levelPaths = UnityEditor.AssetDatabase.GetAssetPathsFromAssetBundleAndAssetName(
                assetBundleName, levelName);
            if (levelPaths.Length == 0)
            {
                Debug.LogError($"There is no scene with name \"{levelName}\" in {assetBundleName}");
                return;
            }

            var mode = isAdditive ? LoadSceneMode.Additive : LoadSceneMode.Single;
            _operation = UnityEditor.SceneManagement.EditorSceneManager.LoadSceneAsyncInPlayMode(
                levelPaths[0], new LoadSceneParameters(mode));
        }

        public override bool Update() { return false; }
        public override bool IsDone() { return _operation == null || _operation.isDone; }
    }
#endif

    public class AssetBundleLoadLevelOperation : AssetBundleLoadOperation
    {
        private string _assetBundleName;
        private string _levelName;
        private bool _isAdditive;
        private string _downloadingError;
        private AsyncOperation _request;

        public AssetBundleLoadLevelOperation(string assetbundleName, string levelName, bool isAdditive)
        {
            _assetBundleName = assetbundleName;
            _levelName = levelName;
            _isAdditive = isAdditive;
        }

        public override bool Update()
        {
            if (_request != null) return false;

            var bundle = AssetBundleManager.GetLoadedAssetBundle(_assetBundleName, out _downloadingError);
            if (bundle != null)
            {
                _request = SceneManager.LoadSceneAsync(_levelName,
                    _isAdditive ? LoadSceneMode.Additive : LoadSceneMode.Single);
                return false;
            }
            return _downloadingError == null;
        }

        public override bool IsDone()
        {
            if (_request == null && _downloadingError != null)
            {
                Debug.LogError(_downloadingError);
                return true;
            }
            return _request != null && _request.isDone;
        }
    }

    public abstract class AssetBundleLoadAssetOperation : AssetBundleLoadOperation
    {
        public abstract T GetAsset<T>() where T : Object;
    }

#if UNITY_EDITOR
    public class AssetBundleLoadAssetOperationSimulation : AssetBundleLoadAssetOperation
    {
        private Object _simulatedObject;

        public AssetBundleLoadAssetOperationSimulation(Object simulatedObject)
        {
            _simulatedObject = simulatedObject;
        }

        public override T GetAsset<T>()
        {
            return _simulatedObject as T;
        }

        public override bool Update() { return false; }
        public override bool IsDone() { return true; }
    }
#endif

    public class AssetBundleLoadAssetOperationFull : AssetBundleLoadAssetOperation
    {
        private string _assetBundleName;
        private string _assetName;
        private string _downloadingError;
        private System.Type _type;
        private AssetBundleRequest _request;

        public AssetBundleLoadAssetOperationFull(string bundleName, string assetName, System.Type type)
        {
            _assetBundleName = bundleName;
            _assetName = assetName;
            _type = type;
        }

        public override T GetAsset<T>()
        {
            if (_request != null && _request.isDone)
                return _request.asset as T;
            return null;
        }

        public override bool Update()
        {
            if (_request != null) return false;

            var bundle = AssetBundleManager.GetLoadedAssetBundle(_assetBundleName, out _downloadingError);
            if (bundle != null)
            {
                _request = bundle.m_AssetBundle.LoadAssetAsync(_assetName, _type);
                return false;
            }
            return _downloadingError == null;
        }

        public override bool IsDone()
        {
            return _downloadingError != null || (_request != null && _request.isDone);
        }
    }

    public class AssetBundleLoadManifestOperation : AssetBundleLoadAssetOperationFull
    {
        public AssetBundleLoadManifestOperation(string bundleName, string assetName, System.Type type)
            : base(bundleName, assetName, type)
        {
        }

        public override bool Update()
        {
            base.Update();

            if (IsDone())
            {
                AssetBundleManager.AssetBundleManifestObject = GetAsset<AssetBundleManifest>();
                return false;
            }
            return true;
        }
    }
}
