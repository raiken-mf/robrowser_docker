addEventListener(
	'message',
	function OnMessage(event) {
		// Only accept messages from the parent window or opener (the page that loaded us)
		if (event.source !== window.parent && event.source !== window.opener) {
			return;
		}

		removeEventListener('message', OnMessage, false);

		window.ROConfig = event.data;

		// Load the engine entry point as an ES6 module
		import('../../src/main.js')
			.then(() => {
				event.source.postMessage('ready', '*');
			})
			.catch(err => {
				console.error('Failed to load roBrowser engine:', err);
			});
	},
	false
);
