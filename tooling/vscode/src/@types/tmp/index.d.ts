declare module 'tmp' {
    type Options = {
        keep: boolean | null;
        tries: number | null;
        template: string | null;
        name: string | null;
        dir: string | null;
        prefix: string | null;
        postfix: string | null;
        tmpdir: string | null;
        unsafeCleanup: boolean | null;
        detachDescriptor: boolean | null;
        discardDescriptor: boolean | null;
    }
    type simpleCallback = () => any
    type cleanupCallback = (next?: simpleCallback) => any
    type fileCallback = (err: Error | null, name: string, fd: number, fn: cleanupCallback) => any
    type DirSyncObject = {
        name: string;
        removeCallback: fileCallback;
    }
    export function dirSync(options?: Options): DirSyncObject
}