import { InsufficientScopeError, TokenExpiredError } from "./youtube";

/* The Drive app folder: files only this app's OAuth clients can see. */
const FILES_ENDPOINT = "https://www.googleapis.com/drive/v3/files";
const UPLOAD_ENDPOINT = "https://www.googleapis.com/upload/drive/v3/files";
const ABOUT_ENDPOINT = "https://www.googleapis.com/drive/v3/about";

/** A file in the Drive app folder. */
export interface DriveFile {
  /** Drive file id */
  id: string;
  /** file name */
  name: string;
  /** RFC 3339 time of the last change */
  modifiedTime: string;
}

async function driveFetch(
  url: string,
  token: string,
  init: RequestInit = {},
): Promise<Response> {
  const response = await fetch(url, {
    ...init,
    headers: { ...init.headers, Authorization: `Bearer ${token}` },
  });
  if (response.status === 401) {
    throw new TokenExpiredError();
  }
  if (!response.ok) {
    const body = await response.text();
    if (response.status === 403 && body.includes("insufficient")) {
      throw new InsufficientScopeError();
    }
    console.error(`Google Drive request failed: ${response.status} ${body}`);
    throw new Error(`Google request failed: ${response.status}`);
  }
  return response;
}

/** The Google account behind a token, as Drive reports it. */
export interface DriveUser {
  /** the account's name */
  displayName: string;
  /** the account's address, when Drive shares it */
  emailAddress?: string;
}

/** The signed-in Google account's name and address; the app-folder scope is enough to ask. */
export async function fetchDriveUser(token: string): Promise<DriveUser> {
  const url = `${ABOUT_ENDPOINT}?fields=${encodeURIComponent("user(displayName,emailAddress)")}`;
  const data = (await (await driveFetch(url, token)).json()) as {
    user: DriveUser;
  };
  return data.user;
}

/** Every file in the app folder. */
export async function listAppFiles(token: string): Promise<DriveFile[]> {
  const files: DriveFile[] = [];
  let pageToken: string | undefined;
  do {
    const url = new URL(FILES_ENDPOINT);
    url.search = new URLSearchParams({
      spaces: "appDataFolder",
      fields: "nextPageToken,files(id,name,modifiedTime)",
      pageSize: "100",
      ...(pageToken ? { pageToken } : {}),
    }).toString();
    const data = (await (await driveFetch(url.toString(), token)).json()) as {
      files: DriveFile[];
      nextPageToken?: string;
    };
    files.push(...data.files);
    pageToken = data.nextPageToken;
  } while (pageToken);
  return files;
}

/** Delete a file from the app folder; one already gone counts as deleted. */
export async function deleteFile(fileId: string, token: string): Promise<void> {
  const response = await fetch(
    `${FILES_ENDPOINT}/${encodeURIComponent(fileId)}`,
    { method: "DELETE", headers: { Authorization: `Bearer ${token}` } },
  );
  if (response.status === 401) {
    throw new TokenExpiredError();
  } else if (!response.ok && response.status !== 404) {
    throw new Error(`Google request failed: ${response.status}`);
  }
}

/** A file's content, parsed as JSON. */
export async function downloadJson(
  fileId: string,
  token: string,
): Promise<unknown> {
  const response = await driveFetch(
    `${FILES_ENDPOINT}/${encodeURIComponent(fileId)}?alt=media`,
    token,
  );
  return response.json();
}

/** Create a JSON file in the app folder, returning its id and modified time. */
export async function createJson(
  name: string,
  content: unknown,
  token: string,
): Promise<DriveFile> {
  const boundary = `subtube-${crypto.randomUUID()}`;
  const body = [
    `--${boundary}`,
    "Content-Type: application/json; charset=UTF-8",
    "",
    JSON.stringify({ name, parents: ["appDataFolder"] }),
    `--${boundary}`,
    "Content-Type: application/json",
    "",
    JSON.stringify(content),
    `--${boundary}--`,
  ].join("\r\n");
  const response = await driveFetch(
    `${UPLOAD_ENDPOINT}?uploadType=multipart&fields=id,name,modifiedTime`,
    token,
    {
      method: "POST",
      headers: { "Content-Type": `multipart/related; boundary=${boundary}` },
      body,
    },
  );
  return (await response.json()) as DriveFile;
}

/** Replace a file's content, returning its id and modified time. */
export async function updateJson(
  fileId: string,
  content: unknown,
  token: string,
): Promise<DriveFile> {
  const response = await driveFetch(
    `${UPLOAD_ENDPOINT}/${encodeURIComponent(fileId)}?uploadType=media&fields=id,name,modifiedTime`,
    token,
    {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(content),
    },
  );
  return (await response.json()) as DriveFile;
}
