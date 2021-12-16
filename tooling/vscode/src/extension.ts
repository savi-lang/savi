import * as child_process from "child_process";
import { LanguageClient, LanguageClientOptions } from "vscode-languageclient";
import {
  commands,
  Disposable,
  ExtensionContext,
  TextDocument,
  Uri,
  window,
  workspace,
  WorkspaceFolder,
  WorkspaceFoldersChangeEvent,
} from "vscode";

const clients: Map<Uri, SaviClient> = new Map();

export async function activate(ctx: ExtensionContext) {
  workspace.onDidOpenTextDocument((doc) => didOpenTextDocument(doc, ctx));
  workspace.textDocuments.forEach((doc) => didOpenTextDocument(doc, ctx));
  workspace.onDidChangeWorkspaceFolders((e) =>
    didChangeWorkspaceFolders(e, ctx)
  );
}

export async function deactivate() {
  return Promise.all([...clients.values()].map((ws) => ws.stop()));
}

function didOpenTextDocument(document: TextDocument, ctx: ExtensionContext) {
  // Ignore text documents whose language isn't Savi.
  if (document.languageId !== "savi") return;

  // Ignore text documents with no workspace folder associated.
  let folder = workspace.getWorkspaceFolder(document.uri);
  if (!folder) return;

  // Ignore workspace folders we're already tracking.
  if (clients.has(folder.uri)) return;

  // Add a client for the new workspace folder.
  const client = new SaviClient(folder);
  clients.set(folder.uri, client);
  client.start(ctx);
}

function didChangeWorkspaceFolders(
  e: WorkspaceFoldersChangeEvent,
  ctx: ExtensionContext
) {
  // Add a client for each workspace folder that is new.
  for (const folder of e.added) {
    if (!clients.has(folder.uri)) {
      const client = new SaviClient(folder);
      clients.set(folder.uri, client);
      client.start(ctx);
    }
  }

  // Clean up clients for workspace folders that were closed.
  for (const folder of e.removed) {
    const ws = clients.get(folder.uri);
    if (ws) {
      clients.delete(folder.uri);
      ws.stop();
    }
  }
}

class SaviClient {
  private disposables: Disposable[] = [];
  private client: LanguageClient | null = null;
  private readonly folder: WorkspaceFolder;

  constructor(folder: WorkspaceFolder) {
    this.folder = folder;
  }

  private get clientOptions(): LanguageClientOptions {
    return {
      documentSelector: [
        { language: "savi", scheme: "file" },
        { language: "savi", scheme: "untitled" },
      ],
      diagnosticCollectionName: "savi",
      synchronize: { configurationSection: "savi" },
      initializationOptions: {
        omitInitBuild: true,
        cmdRun: true,
      },
      workspaceFolder: this.folder,
    };
  }

  public async start(ctx: ExtensionContext) {
    this.client = new LanguageClient(
      "savi-client",
      "Savi Language Server",
      async () => {
        return this.spawnServer();
      },
      this.clientOptions
    );

    this.disposables.push(
      commands.registerCommand("savi.restart", async () => {
        await this.stop();
        return this.start(ctx);
      })
    );

    this.disposables.push(this.client.start());
    await this.client.onReady();
  }

  public async stop() {
    if (this.client) await this.client.stop();

    this.disposables.forEach((d) => d.dispose());
  }

  private async spawnServer(): Promise<child_process.ChildProcess> {
    const cwd = this.folder.uri.fsPath;
    const env = { ...process.env };

    let serverProcess = child_process.spawn("savi", ["server"], { env, cwd });

    serverProcess.on("error", (err: { code?: string; message: string }) => {
      window.showWarningMessage(
        `Failed to spawn Savi Language Server: \`${err.message}\``
      );
    });

    return serverProcess;
  }
}
