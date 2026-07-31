import { randomUUID } from "node:crypto";
import {
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

export interface UploadGrant {
  objectKey: string;
  uploadURL: string;
  expiresAt: Date;
  requiredHeaders: Record<string, string>;
}

export interface TemporaryObjectStore {
  createUploadGrant(input: {
    contentType: string;
    contentLength: number;
    digest: string;
    expiresAt: Date;
  }): Promise<UploadGrant>;
  verifyUpload(input: {
    objectKey: string;
    contentType: string;
    contentLength: number;
    digest: string;
  }): Promise<boolean>;
  createDownloadURL(objectKey: string, expiresAt: Date): Promise<string>;
  deleteObjects(keys: string[]): Promise<void>;
}

export class InMemoryObjectStore implements TemporaryObjectStore {
  readonly deletedKeys: string[] = [];

  async createUploadGrant(input: {
    contentType: string;
    contentLength: number;
    digest: string;
    expiresAt: Date;
  }): Promise<UploadGrant> {
    const objectKey = `temporary/${randomUUID()}`;
    return {
      objectKey,
      uploadURL: `https://uploads.invalid/${objectKey}`,
      expiresAt: input.expiresAt,
      requiredHeaders: {
        "content-type": input.contentType,
        "content-length": String(input.contentLength),
        "x-content-sha256": input.digest,
      },
    };
  }

  async deleteObjects(keys: string[]): Promise<void> {
    this.deletedKeys.push(...keys);
  }

  async verifyUpload(): Promise<boolean> {
    return true;
  }

  async createDownloadURL(objectKey: string): Promise<string> {
    return `https://uploads.invalid/${objectKey}`;
  }
}

export class S3TemporaryObjectStore implements TemporaryObjectStore {
  private readonly client: S3Client;

  constructor(
    private readonly bucket: string,
    input: {
      region: string;
      endpoint?: string;
    },
  ) {
    this.client = new S3Client({
      region: input.region,
      ...(input.endpoint === undefined
        ? {}
        : {
            endpoint: input.endpoint,
            forcePathStyle: true,
          }),
    });
  }

  async createUploadGrant(input: {
    contentType: string;
    contentLength: number;
    digest: string;
    expiresAt: Date;
  }): Promise<UploadGrant> {
    const objectKey = `temporary/${randomUUID()}`;
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: objectKey,
      ContentType: input.contentType,
      ContentLength: input.contentLength,
      ChecksumSHA256: Buffer.from(input.digest, "hex").toString("base64"),
    });
    const expiresIn = Math.max(
      Math.floor((input.expiresAt.getTime() - Date.now()) / 1_000),
      1,
    );
    return {
      objectKey,
      uploadURL: await getSignedUrl(this.client, command, { expiresIn }),
      expiresAt: input.expiresAt,
      requiredHeaders: {
        "content-type": input.contentType,
        "content-length": String(input.contentLength),
        "x-amz-checksum-sha256": Buffer.from(
          input.digest,
          "hex",
        ).toString("base64"),
      },
    };
  }

  async deleteObjects(keys: string[]): Promise<void> {
    if (keys.length === 0) return;
    await this.client.send(new DeleteObjectsCommand({
      Bucket: this.bucket,
      Delete: {
        Objects: keys.map((Key) => ({ Key })),
        Quiet: true,
      },
    }));
  }

  async verifyUpload(input: {
    objectKey: string;
    contentType: string;
    contentLength: number;
    digest: string;
  }): Promise<boolean> {
    try {
      const result = await this.client.send(new HeadObjectCommand({
        Bucket: this.bucket,
        Key: input.objectKey,
        ChecksumMode: "ENABLED",
      }));
      const expectedChecksum = Buffer.from(input.digest, "hex").toString(
        "base64",
      );
      return (
        result.ContentLength === input.contentLength &&
        result.ContentType === input.contentType &&
        result.ChecksumSHA256 === expectedChecksum
      );
    } catch {
      return false;
    }
  }

  async createDownloadURL(
    objectKey: string,
    expiresAt: Date,
  ): Promise<string> {
    const expiresIn = Math.max(
      Math.floor((expiresAt.getTime() - Date.now()) / 1_000),
      1,
    );
    return getSignedUrl(
      this.client,
      new GetObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
      }),
      { expiresIn },
    );
  }
}

export const allowedUploadTypes = new Set([
  "image/jpeg",
  "image/heic",
  "image/png",
  "video/quicktime",
  "video/mp4",
]);

export const maximumUploadBytes = 100 * 1_024 * 1_024;
