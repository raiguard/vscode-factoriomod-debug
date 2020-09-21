import * as vscode from 'vscode';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as Git from './git';
import * as WebRequest from 'web-request';
import * as semver from 'semver';
import { jar } from 'request';
import { spawn } from 'child_process';
import { BufferSplitter } from './BufferSplitter';
import { ModManager } from './ModManager';

let archiver = require('archiver');

interface ModPackageScripts {
	compile?: string
	datestamp?: string
	prepackage?: string
	version?: string
	prepublish?: string
	publish?: string
};

export interface ModInfo {
	name: string
	version: string
	factorio_version: string
	title: string
	author: string
	homepage: string
	contact: string
	description: string
	dependencies: string[]
	package?: {
		ignore?: string[]
		no_git_push?: boolean
		git_publish_branch?: string|null
		no_portal_upload?: boolean
		scripts?: ModPackageScripts
	}
};

interface AdjustModsDefinition extends vscode.TaskDefinition {
	type: "factorio"
	command: "adjustMods"
	adjustMods: {[keys:string]:string|boolean}
	modsPath: string
	disableExtraMods?:boolean
	allowDisableBaseMod?:boolean
}

export class ModTaskProvider implements vscode.TaskProvider{
	private readonly modPackages: Map<string, ModPackage>;

	constructor(context: vscode.ExtensionContext, modPackages: Map<string, ModPackage>) {
		this.modPackages = modPackages;
	}
	provideTasks(token?: vscode.CancellationToken | undefined): vscode.ProviderResult<vscode.Task[]> {
		let tasks:vscode.Task[] = [];

		this.modPackages.forEach((mp,uri) => {
			if (mp.scripts?.compile)
			{
				tasks.push(new vscode.Task(
					{label:`${mp.label}.compile`,type:"factorio",modname:mp.label,command:"compile"},
					vscode.workspace.getWorkspaceFolder(mp.resourceUri) || vscode.TaskScope.Workspace,
					`${mp.label}.compile`,
					"factorio",
					mp.CompileTask(),
					[]
				));
			}
			tasks.push(new vscode.Task(
				{label:`${mp.label}.datestamp`,type:"factorio",modname:mp.label,command:"datestamp"},
				vscode.workspace.getWorkspaceFolder(mp.resourceUri) || vscode.TaskScope.Workspace,
				`${mp.label}.datestamp`,
				"factorio",
				mp.DateStampTask(),
				[]
			));
			tasks.push(new vscode.Task(
				{label:`${mp.label}.package`,type:"factorio",modname:mp.label,command:"package"},
				vscode.workspace.getWorkspaceFolder(mp.resourceUri) || vscode.TaskScope.Workspace,
				`${mp.label}.package`,
				"factorio",
				mp.PackageTask(),
				[]
			));
			tasks.push(new vscode.Task(
				{label:`${mp.label}.version`,type:"factorio",modname:mp.label,command:"version"},
				vscode.workspace.getWorkspaceFolder(mp.resourceUri) || vscode.TaskScope.Workspace,
				`${mp.label}.version`,
				"factorio",
				mp.IncrementTask(),
				[]
			));
			tasks.push(new vscode.Task(
				{label:`${mp.label}.upload`,type:"factorio",modname:mp.label,command:"upload"},
				vscode.workspace.getWorkspaceFolder(mp.resourceUri) || vscode.TaskScope.Workspace,
				`${mp.label}.upload`,
				"factorio",
				mp.PostToPortalTask(),
				[]
			));
			tasks.push(new vscode.Task(
				{label:`${mp.label}.publish`,type:"factorio",modname:mp.label,command:"publish"},
				vscode.workspace.getWorkspaceFolder(mp.resourceUri) || vscode.TaskScope.Workspace,
				`${mp.label}.publish`,
				"factorio",
				mp.PublishTask(),
				[]
			));

		},this);

		return tasks;
	}

	resolveTask(task: vscode.Task, token?: vscode.CancellationToken | undefined): vscode.ProviderResult<vscode.Task> {
		if (task.definition.type === "factorio")
		{
			if (task.definition.command === "adjustMods")
			{
				if (!task.definition.adjustMods) { return undefined; }
				if (!task.definition.modsPath) { return undefined; }
				return new vscode.Task(
					task.definition,
					task.scope || vscode.TaskScope.Workspace,
					task.name,
					task.source,
					this.AdjustModsTask(<AdjustModsDefinition>task.definition),
					[]
				);
			}
			else
			{
				if (!task.definition.modname) { return undefined; }
				for (const modpackage of this.modPackages.values()) {
					if (modpackage.label === task.definition.modname) {
						const mp = modpackage;
						let execution:vscode.CustomExecution;
						switch (task.definition.command) {
							case "compile":
								execution = mp.CompileTask();
								break;
							case "datestamp":
								execution = mp.DateStampTask();
								break;
							case "package":
								execution = mp.PackageTask();
								break;
							case "version":
								execution = mp.IncrementTask();
								break;
							case "upload":
								execution = mp.PostToPortalTask();
								break;
							case "publish":
								execution = mp.PublishTask();
								break;
							default:
								return undefined;
						}
						return new vscode.Task(
							task.definition,
							task.scope || vscode.TaskScope.Workspace,
							task.name,
							task.source,
							execution,
							[]
						);
					}
				}
			}
		}
		return undefined;
	}


	private async AdjustMods(term:ModTaskTerminal,def:AdjustModsDefinition): Promise<void>
	{
		const manager = new ModManager(def.modsPath);
		if (!def.allowDisableBaseMod) {def.adjustMods["base"] = true;}
		if (def.disableExtraMods) {
			manager.disableAll();
		}
		for (const mod in def.adjustMods) {
			if (def.adjustMods.hasOwnProperty(mod))
			{
				const adjust = def.adjustMods[mod];
				manager.set(mod,adjust);
			}
		}
		manager.write();
	}

	private AdjustModsTask(def:AdjustModsDefinition): vscode.CustomExecution
	{
		return new vscode.CustomExecution(async ()=>{
			return new ModTaskPseudoterminal(async term =>{
				await this.AdjustMods(term,def);
				term.close();
			});
		});
	}
}

export class ModPackage extends vscode.TreeItem {
	public label: string; // used as modname
	public description: string; // used as modversion
	public resourceUri: vscode.Uri;
	public packageIgnore?: string[];
	public noGitPush?: boolean;
	public gitPublishBranch?: string|null;
	public noPortalUpload?: boolean;
	public scripts?: ModPackageScripts;

	constructor(uri: vscode.Uri, modscript: ModInfo) {
		super(uri);
		this.label = modscript.name;
		this.description = modscript.version;
		this.tooltip = modscript.title;
		this.contextValue = "factoriomodpackage";
		this.command = {
			title: 'Open',
			command: 'vscode.open',
			arguments: [uri]
		};
		//this.id = modscript.name;
		this.packageIgnore = modscript.package?.ignore;
		this.noGitPush = modscript.package?.no_git_push;
		this.gitPublishBranch = modscript.package?.git_publish_branch;
		this.noPortalUpload = modscript.package?.no_portal_upload;
		this.scripts = modscript.package?.scripts;
	}

	public async Update()
	{
		const infodoc = await vscode.workspace.openTextDocument(this.resourceUri);
		const modscript: ModInfo = JSON.parse(infodoc.getText());

		this.label = modscript.name;
		this.description = modscript.version;
		this.tooltip = modscript.title;
		this.packageIgnore = modscript.package?.ignore;
		this.noGitPush = modscript.package?.no_git_push;
		this.gitPublishBranch = modscript.package?.git_publish_branch;
		this.noPortalUpload = modscript.package?.no_portal_upload;
		this.scripts = modscript.package?.scripts;
	}

	private async Compile(term:ModTaskTerminal): Promise<void>
	{
		const moddir = path.dirname(this.resourceUri.fsPath);
		if(this.scripts?.compile)
		{
			term.write(`Compiling: ${this.resourceUri} ${this.description}\r\n`);

			let code = await runScript(term, "compile", this.scripts.compile, moddir,
				{ FACTORIO_MODNAME:this.label, FACTORIO_MODVERSION:this.description });
			if (code !== 0) {return;}
		}
	}

	public CompileTask(): vscode.CustomExecution
	{
		return new vscode.CustomExecution(async ()=>{
			return new ModTaskPseudoterminal(async term =>{
				await this.Update();
				await this.Compile(term);
				term.close();
			});
		});
	}

	private async DateStampChangelog(term:ModTaskTerminal): Promise<boolean>
	{
		const moddir = path.dirname(this.resourceUri.fsPath);
		const changelogpath = path.join(moddir, "changelog.txt");
		if(fs.existsSync(changelogpath))
		{
			//datestamp current section
			let changelogdoc = await vscode.workspace.openTextDocument(changelogpath);
			let syms = <vscode.DocumentSymbol[]>await vscode.commands.executeCommand<(vscode.SymbolInformation|vscode.DocumentSymbol)[]>("vscode.executeDocumentSymbolProvider", changelogdoc.uri);
			let current = syms?.find(sym=>sym.name.startsWith(this.description))!;
			if (current)
			{
				let date = current.children.find(sym=>sym.name === "Date");
				let we = new vscode.WorkspaceEdit();
				if (date)
				{
					we.replace(changelogdoc.uri,date.selectionRange, new Date().toISOString().substr(0,10));
				}
				else
				{
					we.insert(changelogdoc.uri,current.selectionRange.end,`\nDate: ${new Date().toISOString().substr(0,10)}`);
				}
				await vscode.workspace.applyEdit(we);
				await changelogdoc.save();
				term.write(`Changelog section ${this.description} stamped ${new Date().toISOString().substr(0,10)}\r\n`);
			}
			else
			{
				term.write(`No Changelog section for ${this.description}\r\n`);
			}
			if (this.scripts?.datestamp) {
				await runScript(term, "datestamp", this.scripts.datestamp, moddir,
					{ FACTORIO_MODNAME:this.label, FACTORIO_MODVERSION:this.description });
			}
			return true;
		}
		else
		{
			term.write(`No Changelog found\r\n`);
			if (this.scripts?.datestamp) {
				await runScript(term, "datestamp", this.scripts.datestamp, moddir,
					{ FACTORIO_MODNAME:this.label, FACTORIO_MODVERSION:this.description });
			}
			return false;
		}
	}

	public DateStampTask(): vscode.CustomExecution
	{
		return new vscode.CustomExecution(async ()=>{
			return new ModTaskPseudoterminal(async term =>{
				await this.Update();
				await this.DateStampChangelog(term);
				term.close();
			});
		});
	}

	private async Package(term:ModTaskTerminal): Promise<string|undefined>
	{
		const config = vscode.workspace.getConfiguration(undefined,this.resourceUri);

		term.write(`Packaging: ${this.resourceUri} ${this.description}\r\n`);
		await this.Compile(term);
		const moddir = path.dirname(this.resourceUri.fsPath);
		if(this.scripts?.prepackage)
		{
			let code = await runScript(term, "prepackage", this.scripts.prepackage, moddir,
				{ FACTORIO_MODNAME:this.label, FACTORIO_MODVERSION:this.description });
			if (code !== 0) {return;}
		}
		let packagebase = moddir;
		switch (config.get<string>("factorio.package.zipLocation","inside")) {
			case "outside":
				packagebase = path.dirname(moddir);
				break;
			case "inside":
			default:
				break;
		}

		const packagepath = path.join(packagebase, `${this.label}_${this.description}.zip`);
		let zipoutput = fs.createWriteStream(packagepath);
		let archive = archiver('zip', { zlib: { level: 9 }});
		archive.pipe(zipoutput);
		archive.glob("**",{ cwd: moddir, root: moddir, nodir: true, ignore: [`**/${this.label}_*.zip`].concat(this.packageIgnore||[]) },{ prefix: `${this.label}_${this.description}` });
		let bytesWritten = await new Promise((resolve,reject)=>{
			zipoutput.on("close",()=>resolve(archive.pointer()));
			archive.finalize();
		});
		term.write(`Built ${this.label}_${this.description}.zip ${bytesWritten} bytes\r\n`);
		return packagepath;
	}

	public PackageTask(): vscode.CustomExecution
	{
		return new vscode.CustomExecution(async ()=>{
			return new ModTaskPseudoterminal(async term =>{
				await this.Update();
				await this.Package(term);
				term.close();
			});
		});
	}


	private async IncrementVersion(term:ModTaskTerminal): Promise<string|undefined>
	{
		let we = new vscode.WorkspaceEdit();
		// increment info.json version
		const infodoc = await vscode.workspace.openTextDocument(this.resourceUri);
		const syms = await vscode.commands.executeCommand<(vscode.SymbolInformation|vscode.DocumentSymbol)[]>
												("vscode.executeDocumentSymbolProvider", this.resourceUri);

		if (!syms)
		{
			term.write(`Error: Unable to load document symbols for ${this.resourceUri}\r\n`);
			return;
		}

		const newversion = semver.inc(this.description,'patch')!;
		let version = syms.find(sym=>sym.name === "version")!;

		we.replace(this.resourceUri,
			version instanceof vscode.SymbolInformation ? version.location.range : version.selectionRange,
			`"version": "${newversion}"`);

		const moddir = path.dirname(this.resourceUri.fsPath);
		const changelogpath = path.join(moddir, "changelog.txt");
		let changelogdoc: vscode.TextDocument|undefined;
		if(fs.existsSync(changelogpath))
		{
			//datestamp current section
			changelogdoc = await vscode.workspace.openTextDocument(changelogpath);
			//insert new section
			we.insert(changelogdoc.uri,new vscode.Position(0,0),
			"---------------------------------------------------------------------------------------------------\n" +
			`Version: ${newversion}\n` +
			"Date: ????\n" +
			"  Changes:\n"
			// no placeholder line because prefix alone is not valid...
			);
		}
		await vscode.workspace.applyEdit(we);
		await infodoc.save();
		// eslint-disable-next-line no-unused-expressions
		changelogdoc && await changelogdoc.save();
		term.write(`Moved version to ${newversion}\r\n`);
		if (this.scripts?.version) {
			await runScript(term, "version", this.scripts.version, moddir,
			{ FACTORIO_MODNAME:this.label, FACTORIO_MODVERSION:newversion });
		}
		return newversion;
	}

	public IncrementTask(): vscode.CustomExecution
	{
		return new vscode.CustomExecution(async ()=>{
			return new ModTaskPseudoterminal(async term =>{
				await this.Update();
				await this.IncrementVersion(term);
				term.close();
			});
		});
	}

	private async PostToPortal(packagepath: string, packageversion:string, term:ModTaskTerminal): Promise<boolean>
	{
		// upload to portal
		// TS says this type doesn't work, but it really does...
		let cookiejar = <WebRequest.CookieJar><unknown>jar();
		try {
			const loginform = await WebRequest.get("https://factorio.com/login?mods=1&next=%2Ftrending",{jar:cookiejar});
			const logintoken = ((loginform.content.match(/<input [^>]+"csrf_token"[^>]+>/)||[])[0]?.match(/value="([^"]*)"/)||[])[1];
			const config = vscode.workspace.getConfiguration(undefined,this.resourceUri);

			const username = config.get("factorio.portal.username")
				|| process.env["FACTORIO_PORTAL_USERNAME"]
				|| await vscode.window.showInputBox({prompt: "Mod Portal Username:", ignoreFocusOut: true });
			if(!username) {return false;}

			term.write(`Logging in to Mod Portal as '${username}'\r\n`);

			const password = config.get("factorio.portal.password")
				|| process.env["FACTORIO_PORTAL_PASSWORD"]
				|| await vscode.window.showInputBox({prompt: "Mod Portal Password:", password: true, ignoreFocusOut: true });
			if (!password) {return false;}

			const loginresult = await WebRequest.post("https://factorio.com/login",{jar:cookiejar, throwResponseError: true,
				headers:{
					referer: "https://factorio.com/login?mods=1&next=%2Ftrending"
				},
				form:{
					csrf_token: logintoken,
					username_or_email: username,
					password: password,
					next_url: "/trending",
					next_mods: false
				}
			});

			const loginerr = loginresult.content.match(/<ul class="flashes">[\s\n]*<li>(.*)<\/li>/);
			if (loginerr) {throw new Error(loginerr[1]);}

		} catch (error) {
			term.write(`Failed to log in to Mod Portal: \r\n${error.toString()}\r\n`);
			return false;
		}

		let uploadtoken;
		try {
			const uploadform = await WebRequest.get(`https://mods.factorio.com/mod/${this.label}/downloads/edit`,{jar:cookiejar, throwResponseError: true});
			uploadtoken = uploadform.content.match(/\n\s*token:\s*'([^']*)'/)![1];
		} catch (error) {
			term.write("Failed to get upload token from Mod Portal: " + error.toString());
			return false;
		}

		let uploadresult;
		try {
			uploadresult = await WebRequest.post(`https://direct.mods-data.factorio.com/upload/mod/${uploadtoken}`, {jar:cookiejar, throwResponseError: true,
			formData:{
				file:{
					value:  fs.createReadStream(packagepath),
					options: {
						filename: `${this.label}_${packageversion}.zip`,
						contentType: 'application/x-zip-compressed'
					}
				}
			}});
		} catch (error) {
			term.write("Failed to upload zip to Mod Portal: " + error.toString());
			return false;
		}

		let uploadresultjson = JSON.parse(uploadresult.content);

		try {
			const postresult = await WebRequest.post(`https://mods.factorio.com/mod/${this.label}/downloads/edit`, {
				jar:cookiejar, throwResponseError: true,
				form:{
					file:undefined,
					info_json:uploadresultjson.info,
					changelog:uploadresultjson.changelog,
					filename:uploadresultjson.filename,
					file_size: fs.statSync(packagepath).size ,
					thumbnail:uploadresultjson.thumbnail
				}
			});
			if (postresult.statusCode === 302) {
				term.write(`Published ${this.label} version ${packageversion}`);
			}
			else
			{
				let message = postresult.content.match(/category:\s*'error',\s*\n\s*message:\s*'([^']*)'/)![1];
				throw message;
			}
		} catch (error) {
			term.write("Failed to post update to Mod Portal: " + error.toString());
			return false;
		}

		return true;
	}

	public PostToPortalTask(): vscode.CustomExecution
	{
		return new vscode.CustomExecution(async ()=>{
			return new ModTaskPseudoterminal(async term =>{
				await this.Update();
				const moddir = this.resourceUri.with({path: path.posix.dirname(this.resourceUri.path)});
				const direntries = await vscode.workspace.fs.readDirectory(moddir);
				const packages = direntries.filter(([name,type])=>{
					return type === vscode.FileType.File && name.startsWith(this.label) && name.match(/_\d+\.\d+\.\d+\.zip$/);
				}).map(([name,type])=>{return name;}).sort().reverse();
				const packagename = await vscode.window.showQuickPick(packages,{ placeHolder: "Select Package to upload" });
				if (!packagename)
				{
					term.close();
					return;
				}
				const packagepath = path.join(moddir.fsPath,packagename);
				const packageversion = packagename.match(/_([0-9.]+)\.zip/)![1];
				await this.PostToPortal(packagepath,packageversion,term);
				term.close();
			});
		});
	}

	private async Publish(term:ModTaskTerminal)
	{
		term.write(`Publishing: ${this.resourceUri} ${this.description}\r\n`);
		const moddir = path.dirname(this.resourceUri.fsPath);
		const gitExtension = vscode.extensions.getExtension<Git.GitExtension>('vscode.git')!.exports;
		const git = gitExtension.getAPI(1);
		const repo = git.getRepository(this.resourceUri);
		const config = vscode.workspace.getConfiguration(undefined,this.resourceUri);

		const packageversion = this.description;

		if (repo)
		{
			// throw if uncommitted changes
			if (repo.state.workingTreeChanges.length > 0)
			{
				term.write("Cannot Publish with uncommitted changes\r\n");
				return;
			}
			if (this.gitPublishBranch !== null)
			{
				const branchname = this.gitPublishBranch ?? "master";
				// throw if not on master
				if (repo.state.HEAD?.name !== branchname)
				{
					term.write(`Cannot Publish on branch other than '${branchname}'\r\n`);
					return;
				}
			}
		}
		else
		{
			term.write("No git repo found\r\n");
		}

		if(this.scripts?.prepublish)
		{
			let code = await runScript(term, "prepublish", this.scripts.prepublish, moddir, { FACTORIO_MODNAME:this.label, FACTORIO_MODVERSION:packageversion });
			if (code !== 0) {return;}
		}

		let haschangelog = await this.DateStampChangelog(term);

		let tagname:string;
		if (repo)
		{
			if(haschangelog) {await runScript(term, undefined, `git add changelog.txt`, moddir);}
			await runScript(term, undefined,
				`git commit --author "${ config.get<string>("factorio.package.autoCommitAuthor")! }" --allow-empty -F -`,
				moddir, undefined,
				config.get<string>("factorio.package.preparingCommitMessage")!.replace(/\$VERSION/g,packageversion).replace(/\$MODNAME/g,this.label));
			tagname = config.get<string>("factorio.package.tagName","$VERSION");
			tagname = tagname.replace(/\$VERSION/g,packageversion).replace(/\$MODNAME/g,this.label);
			if (config.get<boolean>("factorio.package.tagVPrefix"))
			{
				term.write(`Using deprecated option factorio.package.tagVPrefix. Use factorio.package.tagName instead. \r\n`);
				tagname = "v" + tagname;
			}
			let tagmessage = config.get<string>("factorio.package.tagMessage");
			tagmessage = tagmessage?.replace(/\$VERSION/g,packageversion).replace(/\$MODNAME/g,this.label);
			const tagarg = tagmessage ? "-F -" : "-m \"\"";
			await runScript(term, undefined, `git tag -a ${tagname} ${tagarg}`, moddir,undefined,tagmessage);
		}

		// build zip with <factorio.package>
		const packagepath = await this.Package(term);
		if (!packagepath) {return;}

		let newversion = await this.IncrementVersion(term);
		if (!newversion) {return;}

		if(this.scripts?.publish)
		{
			let code = await runScript(term, "publish", this.scripts.publish, moddir, { FACTORIO_MODNAME:this.label, FACTORIO_MODVERSION:packageversion });
			if (code !== 0) {return;}
		}

		if (repo)
		{
			await runScript(term, undefined, `git add info.json`, moddir);
			if(haschangelog) {await runScript(term, undefined, `git add changelog.txt`, moddir);}
			await runScript(term, undefined,
				`git commit --author "${ config.get<string>("factorio.package.autoCommitAuthor")! }" -F -`,
				moddir,undefined,
				config.get<string>("factorio.package.movedToCommitMessage")!.replace(/\$VERSION/g,newversion).replace(/\$MODNAME/g,this.label));


			if(!this.noGitPush)
			{
				const upstream = repo?.state.HEAD?.upstream;
				if (upstream)
				{
					await runScript(term, undefined, `git push ${upstream.remote} master ${tagname!}`, moddir);
				}
				else
				{
					term.write(`no remote set as upstream on master\r\n`);
				}
			}
		}
		if(!this.noPortalUpload)
			{
				if(await this.PostToPortal(packagepath, packageversion, term) &&
					config.get<boolean>("factorio.package.removeZipAfterPublish",false))
				{
					fs.unlinkSync(packagepath);
				}
			}
	}

	public PublishTask(): vscode.CustomExecution
	{
		return new vscode.CustomExecution(async ()=>{
			return new ModTaskPseudoterminal(async term =>{
				await this.Update();
				await this.Publish(term);
				term.close();
			});
		});
	}
}
export class ModsTreeDataProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
	private _onDidChangeTreeData: vscode.EventEmitter<vscode.TreeItem | undefined> = new vscode.EventEmitter<vscode.TreeItem | undefined>();
	readonly onDidChangeTreeData: vscode.Event<vscode.TreeItem | undefined> = this._onDidChangeTreeData.event;

	private modPackages: Map<string, ModPackage>;
	constructor(context: vscode.ExtensionContext) {
		const subscriptions = context.subscriptions;

		this.modPackages = new Map<string, ModPackage>();
		vscode.workspace.findFiles('**/info.json').then(infos => { infos.forEach(this.updateInfoJson, this); });
		let infoWatcher = vscode.workspace.createFileSystemWatcher('**/info.json');
		infoWatcher.onDidChange(this.updateInfoJson, this);
		infoWatcher.onDidCreate(this.updateInfoJson, this);
		infoWatcher.onDidDelete(this.removeInfoJson, this);
		subscriptions.push(infoWatcher);

		context.subscriptions.push(vscode.tasks.registerTaskProvider("factorio",new ModTaskProvider(context, this.modPackages)));

		context.subscriptions.push(
			vscode.commands.registerCommand("factorio.datestamp",async (mp:ModPackage) => {
				let datestamptask = (await vscode.tasks.fetchTasks({type:"factorio"})).find(t=>
					t.definition.command = "datestamp" && t.definition.modname === mp.label)!;
				await vscode.tasks.executeTask(datestamptask);
			}));

		context.subscriptions.push(
			vscode.commands.registerCommand("factorio.package",async (mp:ModPackage) => {
				let packagetask = (await vscode.tasks.fetchTasks({type:"factorio"})).find(t=>
					t.definition.command === "package" && t.definition.modname === mp.label)!;
				await vscode.tasks.executeTask(packagetask);
			}));

		context.subscriptions.push(
			vscode.commands.registerCommand("factorio.version",async (mp:ModPackage) => {
				let versiontask = (await vscode.tasks.fetchTasks({type:"factorio"})).find(t=>
					t.definition.command === "version" && t.definition.modname === mp.label)!;
				await vscode.tasks.executeTask(versiontask);
			}));

		context.subscriptions.push(
			vscode.commands.registerCommand("factorio.upload",async (mp:ModPackage) => {
				let uploadtask = (await vscode.tasks.fetchTasks({type:"factorio"})).find(t=>
					t.definition.command === "upload" && t.definition.modname === mp.label)!;
				await vscode.tasks.executeTask(uploadtask);
			}));

		context.subscriptions.push(
			vscode.commands.registerCommand("factorio.publish",async (mp:ModPackage) => {
				let publishtask = (await vscode.tasks.fetchTasks({type:"factorio"})).find(t=>
					t.definition.command === "publish" && t.definition.modname === mp.label)!;
				await vscode.tasks.executeTask(publishtask);

			}));
	}
	private async updateInfoJson(uri: vscode.Uri) {
		if(uri.scheme === "file")
		{
			const infodoc = await vscode.workspace.openTextDocument(uri);
			const modscript: ModInfo = JSON.parse(infodoc.getText());
			if (modscript.name) {
				if (this.modPackages.has(uri.toString())) {
					await this.modPackages.get(uri.toString())?.Update();
				}
				else
				{
					this.modPackages.set(uri.toString(), new ModPackage(uri, modscript));
				}
			}
			else {
				this.modPackages.delete(uri.toString());
			}
		}
		else {
			this.modPackages.delete(uri.toString());
		}
		this._onDidChangeTreeData.fire(undefined);
	}
	private async removeInfoJson(uri: vscode.Uri) {
		this.modPackages.delete(uri.toString());
		this._onDidChangeTreeData.fire(undefined);
	}
	getTreeItem(element: vscode.TreeItem): vscode.TreeItem | Thenable<vscode.TreeItem> {
		return element;
	}
	getChildren(element?: vscode.TreeItem | undefined): vscode.ProviderResult<vscode.TreeItem[]> {
		if (!element) {
			let items: vscode.TreeItem[] = [];
			if (this.modPackages) {
				this.modPackages.forEach((modscript, uri) => {
					items.push(modscript);
				});
			}
			return items.sort((a:ModPackage,b:ModPackage)=>{
				const namecomp = a.label.toLowerCase().localeCompare(b.label.toLowerCase());
				if (namecomp !== 0) {return namecomp * 100;}

				const vercomp = semver.compare(a.description,b.description);
				if (vercomp !== 0) {return vercomp * 10;}

				if (a.resourceUri<b.resourceUri) {return -1;}
				if (a.resourceUri>b.resourceUri) {return  1;}

				return 0;
			});
		}
		else if (element instanceof ModPackage) {
			return [];
		}
		else {
			return [];
		}
	}
}

interface ModTaskTerminal {
	write(data:string):void
	close():void
}

async function runScript(term:ModTaskTerminal, name:string|undefined, command:string, cwd:string, env?:NodeJS.ProcessEnv,stdin?:string): Promise<number>
{
	const config = vscode.workspace.getConfiguration(undefined,vscode.Uri.parse(cwd) );
	let configenv: Object | undefined;
	let configshell: string | undefined;
	let configautoshell: string | undefined;
	switch (os.platform()) {
		case "win32":
			configenv = config.get<Object>("terminal.integrated.env.windows");
			configshell = config.get<string>("terminal.integrated.shell.windows");
			configautoshell = config.get<string>("terminal.integrated.automationShell.windows");
			break;
		case "darwin":
			configenv = config.get<Object>("terminal.integrated.env.osx");
			configshell = config.get<string>("terminal.integrated.shell.osx");
			configautoshell = config.get<string>("terminal.integrated.automationShell.osx");
			break;
		default:
			configenv = config.get<Object>("terminal.integrated.env.linux");
			configshell = config.get<string>("terminal.integrated.shell.linux");
			configautoshell = config.get<string>("terminal.integrated.automationShell.linux");
			break;
	}

	const scriptenv = Object.assign({}, process.env, configenv, env || {} );

	return new Promise((resolve,reject)=>{
		if(name)
		{
			term.write(`>> Running mod script "${name}": ${command} <<\r\n`);
		}
		else
		{
			term.write(`${command}\r\n`);
		}

		const scriptProc = spawn(command, {
				cwd: cwd,
				env: scriptenv,
				shell: configautoshell ?? configshell ?? true,
				stdio: "pipe"
			});

		const stdout = new BufferSplitter(scriptProc.stdout, Buffer.from("\n"));
		stdout.on("segment", (chunk:Buffer) => {
			term.write(chunk.toString()+"\r\n");
		});
		const stderr = new BufferSplitter(scriptProc.stderr, Buffer.from("\n"));
		stderr.on("segment", (chunk:Buffer) => {
			term.write(chunk.toString()+"\r\n");
		});
		scriptProc.on('close', (code,signal) => {
			if(name)
			{
				term.write(`>> Mod script "${name}" returned ${code} <<\r\n`);
			}
			resolve(code);
		});

		scriptProc.on("error", (error) => {
			if(name)
			{
				term.write(`>> Mod script "${name}" failed: ${error.message} <<\r\n`);
			}
			else
			{
				term.write(`${error.message}\r\n`);
			}
		});

		if (stdin)
		{
			scriptProc.stdin.write(stdin);
		}
		scriptProc.stdin.end();
	});

}

class ModTaskPseudoterminal implements vscode.Pseudoterminal {
	private writeEmitter = new vscode.EventEmitter<string>();
	onDidWrite: vscode.Event<string> = this.writeEmitter.event;
	private closeEmitter = new vscode.EventEmitter<void>();
	onDidClose?: vscode.Event<void> = this.closeEmitter.event;
	private tokensource = new vscode.CancellationTokenSource();

	constructor(
		private runner:(term:ModTaskTerminal,token?:vscode.CancellationToken)=>void|Promise<void>) {
	}

	async open(initialDimensions: vscode.TerminalDimensions | undefined): Promise<void> {
		let writeEmitter = this.writeEmitter;
		let closeEmitter = this.closeEmitter;
		await this.runner({
			write: (data) => writeEmitter.fire(data),
			close: () => closeEmitter.fire()
		}, this.tokensource.token);
		closeEmitter.fire();
	}

	close(): void {
		this.tokensource.cancel();
	}
}
