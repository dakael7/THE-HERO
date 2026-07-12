const { onObjectFinalized } = require("firebase-functions/v2/storage");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const sharp = require("sharp");
const path = require("path");
const os = require("os");
const fs = require("fs");
const { buildDownloadUrl } = require("./storageUrls");

const STORAGE_REGION = "southamerica-west1";

/**
 * Procesa imágenes subidas a Storage:
 * - Solo archivos de imagen
 * - Evita re-procesar imágenes ya convertidas o en carpeta processed/
 * - Genera versión 1200x1200 en WebP y la guarda en processed/<ruta>/*_1200.webp
 */
exports.processImage1200Webp = onObjectFinalized(
  { region: STORAGE_REGION },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType || "";

    if (!filePath) return null;
    if (!contentType.startsWith("image/")) return null;
    if (filePath.endsWith("_1200.webp")) return null;
    if (filePath.startsWith("processed/")) return null;

    const bucket = admin.storage().bucket(object.bucket);
    const fileName = path.basename(filePath);
    const dirName = path.dirname(filePath);
    const tempLocalFile = path.join(os.tmpdir(), fileName);

    const isAd = filePath.startsWith("ads/");
    const isOffer = filePath.startsWith("offers/");
    const metadata = object.metadata || {};

    const baseName = fileName.replace(/\.[^.]+$/, "");
    const processedFileName = isAd
      ? `${baseName}.webp`
      : `${baseName}_1200.webp`;
    const processedDir = path.join("processed", dirName === "." ? "" : dirName);
    const processedPath = path.join(processedDir, processedFileName);
    const tempProcessedFile = path.join(os.tmpdir(), processedFileName);

    try {
      // Descargar original
      await bucket.file(filePath).download({ destination: tempLocalFile });

      const transformer = sharp(tempLocalFile).rotate();

      if (isAd) {
        // Banners: sin resize, solo convertir a WebP
        await transformer
          .toFormat("webp", { quality: 85 })
          .toFile(tempProcessedFile);
      } else {
        // Productos y resto: estandarizar a 1200x1200 WebP (recorte centrado)
        await transformer
          .resize(1200, 1200, { fit: "cover", position: "centre" })
          .toFormat("webp", { quality: 80 })
          .toFile(tempProcessedFile);
      }

      // Subir procesado
      await bucket.upload(tempProcessedFile, {
        destination: processedPath,
        contentType: "image/webp",
        metadata: {
          metadata: {
            processed: "true",
            original: filePath,
          },
        },
      });

      if (isAd) {
        // Crear/actualizar documento en colección de lectura
        const downloadUrl = buildDownloadUrl(bucket.name, processedPath);
        const docId = processedPath
          .replace(/^processed\//, "")
          .replace(/[^\w\-\/.]/g, "_")
          .replace(/\//g, "__");

        const rawOrder = metadata.order;
        const rawActive = metadata.active;
        const order =
          typeof rawOrder === "string" ? parseInt(rawOrder, 10) || 0 : 0;
        const active =
          typeof rawActive === "string"
            ? ["true", "1", "yes"].includes(rawActive.toLowerCase())
            : true;

        await admin.firestore().collection("promo_banners").doc(docId).set(
          {
            imageUrl: downloadUrl,
            order,
            active,
            cacheBuster: admin.firestore.FieldValue.serverTimestamp(),
            storagePath: processedPath,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      if (isOffer) {
        // Crear/actualizar documento de oferta usando el ID del path: offers/{userId}/{offerId}/file
        const segments = filePath.split("/").filter(Boolean);
        const offerId = segments.length >= 3 ? segments[2] : null;
        if (offerId) {
          const downloadUrl = buildDownloadUrl(bucket.name, processedPath);
          const offersCol = admin.firestore().collection("offers");
          await offersCol.doc(offerId).set(
            {
              coverImageUrl: downloadUrl,
              imageUrls: admin.firestore.FieldValue.arrayUnion(downloadUrl),
              storagePath: processedPath,
              cacheBuster: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      }

      logger.info("Imagen procesada", {
        original: filePath,
        processed: processedPath,
      });
    } catch (error) {
      logger.error("Error procesando imagen", { filePath, error });
      throw error;
    } finally {
      // Limpieza local
      if (fs.existsSync(tempLocalFile)) {
        fs.unlinkSync(tempLocalFile);
      }
      if (fs.existsSync(tempProcessedFile)) {
        fs.unlinkSync(tempProcessedFile);
      }
    }

    return null;
  },
);


