using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AtmosphereFeature : ScriptableRendererFeature
{
    private AtmospherePass _atmospherePass;
    public AtmosphereConfig config;

    public override void Create()
    {
        _atmospherePass?.Dispose();
        _atmospherePass = new AtmospherePass();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        _atmospherePass.Setup(config);
        renderer.EnqueuePass(_atmospherePass);
    }

    private void OnDestroy()
    {
        _atmospherePass?.Dispose();
    }
}

public class AtmospherePass : ScriptableRenderPass
{
    const string profilerTag = "AtmosphereLutsPass";
    ProfilingSampler _profilingSampler = new ProfilingSampler(profilerTag);
    ProfilingSampler _profilingSampler2 = new ProfilingSampler("AtmosphereRayMarchPass");
    private AtmospherePrecomputeManager _manager; // I want to decouple the core logic from the URP framework.
    private PerCameraDataManager<AtmosphereData> _perCameraDataManager;
    private AtmosphereConfig _config;

    public AtmospherePass()
    {
        renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        _manager = new AtmospherePrecomputeManager();
        _perCameraDataManager = new PerCameraDataManager<AtmosphereData>();
    }

    public void Setup(AtmosphereConfig config)
    {
        _config = config;
        if (_manager.NeedDepthTexture(_config))
            ConfigureInput(ScriptableRenderPassInput.Depth);
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        var mainLightIndex = renderingData.lightData.mainLightIndex;
        if (mainLightIndex < 0)
        {
            Debug.LogWarning("Atmosphere rendering failed, because I can not find the main light.");
            return;
        }

        var mainLight = renderingData.lightData.visibleLights[mainLightIndex];
        var camera = renderingData.cameraData.camera;
        var data = _perCameraDataManager.GetOrAddData(camera);
        using (new ProfilingScope(cmd, _profilingSampler))
        {
            _manager.PrepareData(cmd, data, _config, camera.transform.position,
                -mainLight.localToWorldMatrix.GetColumn(2));
            _manager.ComputeLuts(cmd, data, _config);
            if (_manager.GetMainLightColor(cmd, data, _config, out var color))
            {
                mainLight.finalColor = color;
                var maxComponent = color.maxColorComponent;
                color /= maxComponent;
                color.a = 1;

                mainLight.light.color = color.gamma;
                mainLight.light.intensity = maxComponent;
                renderingData.lightData.visibleLights[mainLightIndex] = mainLight;
            }

            if (_manager.GetAmbientColor(cmd, data, _config, out var groundColor, out var equatorColor, out var skyColor))
            {
                RenderSettings.ambientMode = AmbientMode.Trilight;
                RenderSettings.ambientSkyColor = skyColor.gamma;
                RenderSettings.ambientEquatorColor = equatorColor.gamma;
                RenderSettings.ambientGroundColor = groundColor.gamma;
            }
        }

        base.OnCameraSetup(cmd, ref renderingData);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
#if UNITY_2020_1_OR_NEWER
        CommandBuffer cmd = CommandBufferPool.Get();
#else
        CommandBuffer cmd = CommandBufferPool.Get(profilerTag);
#endif
        var data = _perCameraDataManager.GetOrAddData(renderingData.cameraData.camera);
        using (new ProfilingScope(cmd, _profilingSampler2))
        {
            if (_manager.RaymarchPass(cmd, data, _config))
            {
                cmd.SetViewProjectionMatrices(renderingData.cameraData.GetViewMatrix(),
                    renderingData.cameraData.GetProjectionMatrix());
            }
        }

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public void Dispose()
    {
        _perCameraDataManager.Dispose();
    }

    [ExecuteAlways]
    public class CameraEventHelper : MonoBehaviour
    {
        public Action<Camera> OnCameraDisable;

        public void OnDisable()
        {
            OnCameraDisable?.Invoke(GetComponent<Camera>());
        }
    }

    private class PerCameraDataManager<T> where T : IDisposable, new()
    {
        private Dictionary<Camera, T> _dataDic = new Dictionary<Camera, T>();

        public T GetOrAddData(Camera camera)
        {
            if (!_dataDic.TryGetValue(camera, out var data))
            {
                data = new T();
                _dataDic.Add(camera, data);
                var cameraEvent = camera.GetComponent<CameraEventHelper>();
                if (cameraEvent == null)
                    cameraEvent = camera.gameObject.AddComponent<CameraEventHelper>();
                cameraEvent.OnCameraDisable = OnCameraDisable;
                cameraEvent.hideFlags = HideFlags.HideInInspector | HideFlags.HideAndDontSave;
            }

            return data;
        }

        public void Dispose()
        {
            foreach (var data in _dataDic.Values)
            {
                data?.Dispose();
            }

            _dataDic.Clear();
        }

        private void OnCameraDisable(Camera camera)
        {
            if (_dataDic.TryGetValue(camera, out var data))
            {
                data.Dispose();
                _dataDic.Remove(camera);
            }
        }
    }
}