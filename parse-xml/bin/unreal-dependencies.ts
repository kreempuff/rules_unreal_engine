import yargs from 'https://deno.land/x/yargs@v17.7.2-deno/deno.ts'
import {Arguments} from 'https://deno.land/x/yargs@v17.7.2-deno/deno-types.ts'
import {GitDependencies} from "../lib/manifest.ts"

yargs(Deno.args)
    .command('setup', 'Moves files from the "git dependencies" cache to their location in an Unreal Engine repo', (yargs: any) => {
        return yargs
            .demandOption("gitdep-cache")
            .demandOption("ue-repo")
            .option("gitdep-cache")
            .option("ue-repo")
            .describe("gitdep-cache", "Path to the folder that contains the git dependencies cache")
            .describe("ue-repo", "Path to the root of the Unreal Engine repo")

    }, async (argv: Arguments) => {
        const engineRepo: string = argv["ue-repo"]
        const gitDepCache: string = argv["gitdep-cache"]
        const gitDeps = `${engineRepo}/Engine/Build/Commit.gitdeps.xml`
        try {
            Deno.statSync(gitDeps)
        } catch (e) {
            if (e instanceof Deno.errors.NotFound) {
                console.error(`File "${gitDeps}" does not exist.`)
                return
            }
            console.error(`Unexpected error while checking if "${gitDeps}" exists: ${e.message}`)
            console.error(e)
            return
        }

        const gitDepsManifest = new GitDependencies(gitDeps, gitDepCache)

        for  (const file of gitDepsManifest.allFiles()/*.filter(filename => filename == ".tgitconfig")*/) {
            const fileBytes = await gitDepsManifest.getFileBytes(file)
            console.log(`Writing ${file} from gitdeps to ${engineRepo}/${file}`)
            Deno.writeFileSync(`${engineRepo}/${file}`, fileBytes, {
                create: true,
                mode: gitDepsManifest.file(file)["@_IsExecutable"] ? 0o755 : 0o644
            })
            console.log(`Wrote ${file} from gitdeps to ${engineRepo}/${file}`)
        }
    })
    .strict()
    .parse()