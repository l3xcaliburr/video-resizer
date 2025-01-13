const apiGatewayId = "{{API_ID}}";
const inputBucket = "{{IN_BUCKET}}";
const outputBucket = "{{OUT_BUCKET}}";

// Show the selected file name
document.getElementById("file").addEventListener("change", (e) => {
  const selectedFileName = e.target.files[0]?.name || "No file selected";
  const fileNameDisplay = document.getElementById("selected-file-name");
  fileNameDisplay.textContent = `Selected file: ${selectedFileName}`;
});

// Function to sleep for a given number of milliseconds
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Function for the progress bar
function updateProgress(text, percentage = null) {
  const progressContainer = document.getElementById("progress-container");
  const progressText = document.getElementById("progress-text");
  const progressFill = document.getElementById("progress-fill");

  progressContainer.classList.remove("hidden");
  progressText.textContent = text;

  if (percentage !== null) {
    progressFill.style.width = `${percentage}%`;
  }
}

async function pollJobStatus(jobId, maxAttempts = 30) {
  const statusEndpoint = `https://${apiGatewayId}.execute-api.us-east-1.amazonaws.com/production/job-status`;

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const response = await fetch(`${statusEndpoint}?jobId=${jobId}`);
    const data = await response.json();

    if (data.status === "COMPLETE") {
      return data.downloadUrl;
    } else if (data.status === "ERROR") {
      throw new Error("Video processing failed");
    }

    await sleep(5000); // Wait 5 seconds between polls
  }

  throw new Error("Timeout waiting for video processing");
}

document.getElementById("upload-form").addEventListener("submit", async (e) => {
  e.preventDefault();

  updateProgress("", 0);

  const fileInput = document.getElementById("file");
  const widthInput = document.getElementById("width"); // Capture width input
  const heightInput = document.getElementById("height"); // Capture height input
  const file = fileInput.files[0];
  const width = parseInt(widthInput.value, 10);
  const height = parseInt(heightInput.value, 10);

  const apiEndpoint = `https://${apiGatewayId}.execute-api.us-east-1.amazonaws.com/production/resize`;
  const presignedUrlEndpoint = `https://${apiGatewayId}.execute-api.us-east-1.amazonaws.com/production/presigned-url`;

  if (!file) {
    alert("Please select a file");
    console.error("No file selected");
    return;
  }

  if (isNaN(width) || isNaN(height) || width <= 0 || height <= 0) {
    alert("Please enter valid width and height values");
    console.error("Invalid width or height");
    return;
  }

  try {
    // Step 1: Request a pre-signed URL
    updateProgress("Requesting pre-signed URL...", 20);
    const presignedUrlResponse = await fetch(
      `${presignedUrlEndpoint}?key=${encodeURIComponent(file.name)}`
    );

    if (!presignedUrlResponse.ok) {
      const errorDetails = await presignedUrlResponse.text();
      console.error("Failed to get pre-signed URL:", errorDetails);
      throw new Error("Failed to get pre-signed URL");
    }

    const { url: presignedUrl } = await presignedUrlResponse.json();

    console.log(presignedUrl);

    // Step 2: Upload the file to S3
    updateProgress("Uploading file to S3...", 40);
    await fetch(presignedUrl, {
      method: "PUT",
      body: file,
      headers: { "Content-Type": "" }, // Force empty content-type headers due to browser behavior
    });

    // Step 3: Notify the backend to process the video
    updateProgress("Processing video...", 60);
    const payload = {
      bucket: inputBucket,
      key: file.name,
      output_bucket: outputBucket,
      output_key: `resized-${file.name}`,
      width: width, // Send width to the backend
      height: height, // Send height to the backend
    };

    const response = await fetch(apiEndpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorDetails = await response.text();
      console.error("Failed to process video:", errorDetails);
      throw new Error("Failed to process video");
    }

    const { jobId } = await response.json();

    // Step 4: Poll for job completion and get download URL
    updateProgress("Waiting for processing to complete...", 80);
    const downloadUrl = await pollJobStatus(jobId);

    // Step 5: Create download link and trigger download
    updateProgress("Download starting...", 100);
    fetch(downloadUrl)
      .then((response) => response.blob())
      .then((blob) => {
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement("a");
        link.href = url;
        link.setAttribute("download", `resized-${file.name}`);
        link.click();
        window.URL.revokeObjectURL(url);
      })
      .catch((err) => {
        updateProgress(`Error: ${err.message}`, 0);
        console.error("Error:", err);
      });

    // Add delay and update the message after 2 seconds
    sleep(2000).then(() => {
      updateProgress("All done! Have a great day.");
    });
  } catch (err) {
    updateProgress(`Error: ${err.message}`, 0);
    console.error("Error:", err);
  }
});
