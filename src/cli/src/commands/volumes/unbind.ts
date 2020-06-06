import {flags} from '@oclif/command'
import Command from '../../base'
import {cli} from 'cli-ux'
const EventsController = require('../../controllers/events/index.js');
import * as inquirer from 'inquirer'
const chalk = require('chalk')

export default class Volume extends Command {
	static description = 'unbind a volume from a resource'
	
	static flags = {
		help: flags.help({char: 'h'}),
		target: flags.string({
			char: 't',
			description: 'Target to unbing the volume from',
			options: ['k8s', 'VM (in construction)']
		})
	}

	static args = [
	  	{	
			name: 'name',
			description: 'The name of the volume'
		}
	]

	/**
	 * run
	 */
	async run() {
		const {args, flags} = this.parse(Volume)
		if(!args.name){
			return this.logError("Missing volume name.");
		}
		let params = {
			target: "",
			name: args.name
		}

		if(!flags.target){
			let responses: any = await inquirer.prompt([{
				name: 'target',
				message: 'Unbind from what target?',
				type: 'list',
				choices: [{name: 'k8s'}],
			}])
			params.target = responses.target;
		} else {
			params.target = flags.target
		}

		let result = await this.api("volume", {
			method: "unbind",
			data: params
		}, (event: any) => {
			if(event.error){
				cli.action.stop();
				cli.action.start(chalk.red(event.value));
			} else {
				cli.action.stop();
				cli.action.start(event.value);
			}
		}, () => {
			cli.action.stop();
		});

		if(result.code != 200){
			EventsController.close();
		}

		if(result.code == 409){
			this.logError(`This volume is not bound to this target`);
		} else if(result.code == 410){
			this.logError(`There are resources claiming this volume. Please remove the concerned resources and try again.`);
		} else if(result.code == 401){
			this.logError(`You are not logged in`);
		} else if(result.code == 412){
			this.logError(`You need to select a workspace first`);
		} else if(result.code == 417){
			this.logError(`The cli API host has not been defined. Please run the command "multipaas join" to specity a target host for MultiPaaS.`);
		} else if(result.code == 425){
			this.logError(`Your cluster is in the process of being updated. Please wait a bit until all tasks are finished to perform further configurations.`);
		} else if(result.code == 503){
			this.logError(`MultiPaaS is not accessible. Please make sure that you are connected to the right network and try again.`);
		} else if(result.code != 200){
			// console.log(result);
			this.logError("Something went wrong... Please inform the system administrator.");
		}
	}
}