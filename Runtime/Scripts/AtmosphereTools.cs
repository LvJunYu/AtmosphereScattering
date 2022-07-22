using UnityEngine;

public static class AtmosphereTools
{
    public static RenderTexture GetRenderTexture(string name, int width, int height, RenderTextureFormat format,
        FilterMode filter, RenderTexture rt, out bool createNew)
    {
        createNew = false;
        if (rt != null)
        {
            if (rt.width != width || rt.height != height || rt.filterMode != filter)
            {
                RenderTexture.ReleaseTemporary(rt);
                rt = null;
            }
        }

        if (rt == null)
        {
            rt = RenderTexture.GetTemporary(width, height, 0, format);
            rt.filterMode = filter;
            rt.name = name;
            createNew = true;
        }

        return rt;
    }

    public static void SafeDestroy(Object o)
    {
        if (o == null) return;
        if (Application.isPlaying)
            Object.Destroy(o);
        else
            Object.DestroyImmediate(o);
    }

    public static float UvToLutTransmittanceParams(float x_r, float topRadius, float bottomRadius)
    {
        // x_r = DecodeUvToRange01(x_r, LutInfo.TransmittanceLutHeight);
        float H = Mathf.Sqrt(topRadius * topRadius - bottomRadius * bottomRadius);
        float rho = H * x_r;
        float viewHeight = Mathf.Sqrt(rho * rho + bottomRadius * bottomRadius);
        return viewHeight;
    }

    public static float LutTransmittanceParamsToUv(float viewHeight, float viewZenithCosAngle, float topRadius,
        float bottomRadius)
    {
        float H = Mathf.Sqrt(Mathf.Max(0f, topRadius * topRadius - bottomRadius * bottomRadius));
        float rho = Mathf.Sqrt(Mathf.Max(0f, viewHeight * viewHeight - bottomRadius * bottomRadius));

        float discriminant = viewHeight * viewHeight * (viewZenithCosAngle * viewZenithCosAngle - 1f) +
                             topRadius * topRadius;
        float d = Mathf.Max(0f, (-viewHeight * viewZenithCosAngle + Mathf.Sqrt(discriminant)));

        float d_min = topRadius - viewHeight;
        float d_max = rho + H;
        float x_mu = (d - d_min) / (d_max - d_min);
        // x_mu = EncodeRange01ToUv(x_mu, LutInfo.TransmittanceLutWidth);

        return x_mu;
    }

    public static float EncodeRange01ToUv(float u, int resolution)
    {
        return (u + 0.5f / resolution) * (resolution / (resolution + 1.0f));
    }

    public static float DecodeUvToRange01(float u, int resolution)
    {
        return (u - 0.5f / resolution) * (resolution / (resolution - 1.0f));
    }
}