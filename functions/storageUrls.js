function buildDownloadUrl(bucketName, filePath) {
  const encodedPath = encodeURIComponent(filePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media`;
}

module.exports = {
  buildDownloadUrl,
};
