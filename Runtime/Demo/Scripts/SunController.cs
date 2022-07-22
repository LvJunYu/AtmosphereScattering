using UnityEngine;

// [ExecuteInEditMode]
class SunController : MonoBehaviour
{
    public Transform DirLightTransform;
    private Vector3 prevMousePos;
    [Range(0f, 1f)] public float moveAngle;
    [Range(0f, 50f)] public float speed = 1f;
    [Range(0f, 1f)] public float progress;
    public Vector2 moveDirection;
    public Vector3 startPos;
    private float lastProgress;

    private void Awake()
    {
        if (DirLightTransform == null)
            DirLightTransform = transform;
    }

    private void Start()
    {
        prevMousePos = Input.mousePosition;
    }

    private void Update()
    {
        if (Input.GetMouseButtonDown(0) || Input.GetMouseButtonDown(1))
        {
            prevMousePos = Input.mousePosition;
        }

        Vector3 curMousePos = Input.mousePosition;
        Vector3 mouseDelta = curMousePos - prevMousePos;
        prevMousePos = curMousePos;

        if (Input.GetMouseButton(0))
        {
            DirLightTransform.Rotate(0, mouseDelta.x * 0.1f, 0, Space.World);
            DirLightTransform.Rotate(mouseDelta.y * 0.1f, 0, 0, Space.Self);
            progress = 0;
            lastProgress = 0;
            startPos = DirLightTransform.eulerAngles;
        }
        else
        {
            var angle = moveAngle * Mathf.PI * 2;
            moveDirection = new Vector3(Mathf.Cos(angle), Mathf.Sin(angle));
            if (progress != lastProgress)
            {
                float delta = (progress - lastProgress) * 360f;
                if (moveDirection.x != 0)
                {
                    delta /= Mathf.Abs(moveDirection.x);
                }

                DirLightTransform.Rotate(0, moveDirection.y * delta, 0, Space.World);
                DirLightTransform.Rotate(moveDirection.x * delta, 0, 0, Space.Self);
            }
            else
            {
                var delta = speed * Time.deltaTime;
                DirLightTransform.Rotate(0, moveDirection.y * delta, 0, Space.World);
                DirLightTransform.Rotate(moveDirection.x * delta, 0, 0, Space.Self);
                if (moveDirection.x != 0)
                {
                    delta *= Mathf.Abs(moveDirection.x);
                }

                progress += delta / 360f;
                // while (progress > 1) progress -= 1;
            }

            lastProgress = progress;
        }
    }
}