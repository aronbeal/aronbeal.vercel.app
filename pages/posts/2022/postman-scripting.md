---
title: Postman custom script importing
description: Lessons learned for custom work involving importing scripts into Postman.
tag: postman, javascript, typescript
date: 2022-04-23
---
## Postman custom script importing

### Background

Where I work currently, we use Swagger as the primary means of documenting how our various endpoints are shaped.  It's not the best solution for working with the API in a stateful fashion (call B depends on criteria established in call A), so to that end, developers can use [Postman](https://www.postman.com/) to hit our API endpoints in a way that can be used to record state locally, and use the returned values as part of other queries.

Initially, we had a simple javascript file added to the collection top level, but I've recently grown disenchanted with that &mdash; it's obvious that a single file will become unusable as the power of this suite grows over times, and I don't like how the script itself is hidden away within the bowels of the Postman export.  Postman does allow external libraries to be imported, but not custom ones, so it took a bit of work to find a solution that would allow us to add a library of code to ease interactions within Script.

In my spare time, I ported the script to a full Typescript implementation, to make it easier for other developers to see how it worked.  The script itself is particular to our needs, for the most part, so it won't really be interesting to others in general.  I'm posting to highlight the few areas that others may find useful.  I won't go into the project in detail - I want to focus on the pain points here.  If you want a guide to setting up a Typescript project and bundling it into a library, there's plenty of guides already out there.

### Building the library

For reference, at the bottom, you can find the file structure[^1], the webpack implementation[^2], and the js packages involved[^3].

The first important thing was how to import the code into the local Postman environment. To do that, I had to dig into the various options available for bundling in webpack for a library. There were a few approaches that could have served, but I ended up choosing `umd`, allowing it be imported in other contexts should the need arise, while still allowing it to be included as a global variable here.

Without going into too much detail, when `yarn build` was run, I had a single minified `*.js` file in my `built` directory called `postman_utils.min.js`, and I would then serve it up locally using a quick-and-dirty express server[^4].  I could then point Postman at that express server URL to fetch the built code, and `eval` it to bring it into scope.[^5]

The code to import that script lives in a Postman **collection**, in the Pre-request section, so that it will be run with every request:

```js

// MAIN
set_global_utils = (pm) => {
    pm.globals.unset('app.utils_script_text');
    const r = pm.response;
    if (r.code !== 200) {
        throw new Error("Could not fetch app utils from postman-utils repo: " + r.code);
    }
    const script_text = r.text();

    eval(script_text);
    const utils = this.PostmanUtilsFactory.default(pm);
    if (typeof utils !== 'object') {
        throw new Error("Utils object not found as expected");
    }
    // Script text is valid, store it.
    pm.globals.set('app.utils_script_text', script_text);
    app.getUtils = () => utils;
    app.hasUtils = () => true;
};

// Default accessor values.
app = {
    hasUtils: () => false,
    getUtils: () => {
        throw new Error("Utils not found");
    }
}

// Populate utils scripts if set.
// Default version will just throw errors.  eval() command will replace this.
// TODO: can probably be combined with the above.
// TODO: try to replace eval() with Function() later, if possible.
let script_text = pm.globals.get('app.utils_script_text');
if (typeof script_text === 'string') {
    // Replaces global utils object.
    eval(script_text);
    utils_factory = this.PostmanUtilsFactory.default;
    delete this.PostmanUtilsFactory.default;
    utils = utils_factory(pm);
    if (typeof utils !== 'object') {
        pm.globals.unset('app.utils_script_text')
        throw new Error("Utils object could not be constructed.  Clearing utils script text.");
    }
    // Script evaluated ok. Replace methods on global object with versions that 
    // return utils.
    app.getUtils = () => utils;
    app.hasUtils = () => true;
}


/**
 * Prerequest: Called before every request in this collection.  Modify as needed.
 */
if (app.hasUtils()) {
    app.getUtils().prerequest(pm);
}
```

This establishes an `app` global variable, with two methods, `hasUtils` and `getUtils`.  `Utils` is my custom code that I'm importing via script.  The default versions of these methods just let the user know they've messed up by not calling an endpoint responsible for fetching the script and storing the script in a [collection](https://learning.postman.com/docs/sending-requests/variables/#defining-collection-variables) variable (so it's available for the whole collection, but not outside of it).

To incorporate this code into my collection, I call a custom endpoint that's responsible for setting up defaults for me:

```js
set_global_utils(pm);
const utils = app.getUtils()
utils.reset({
    // Your environment initializer here.
})
// Whatever utils method is on your script
```

The methods and variables above aren't really important - what's important is that this endpoint is responsible for resetting the state I'm trying to manage to a known baseline, as well as for importing new versions of the script (via `set_global_utils`).  That'll evaluate the script text, and store it in a collection variable.

Here's the most useful realizations I've had while setting all this up:

**Use variables without keyword prefixes**:

Postman [scope](https://learning.postman.com/docs/sending-requests/variables/) allows declaring variables at different levels, but what is not said is that `let` or `const`, when used as a variable prefix, will **hide** that variable from other scopes.  This should come as no surprise, really &mdash; `let` and `const` are block-scoped, so the behaviour is in keeping, but it's not mentioned in the docs, but what caught me off guard is that `var` doesn't work either.  I wanted to declare an `app` variable at the top level that I could reference in other Pre-request or Test script areas.  Removing all declarations solved this issue.

```js
// NO
// var app = {
    // Whatever
// };
// NO
// let app = {
    // Whatever
// };
// NO
// const app = {
    // Whatever
// };
// YES
app = {
    // Whatever
};
```

### Variable scope and referencing

I wanted to be able to store objects in variable scope within Postman, but Postman uses key-value dictionaries for variables, which means I had to be responsible for serializing and deserializing the objects before storing them at the appropriate key.  Postman **also** uses handlebar syntax (e.g. `{{varname}}`) to retrieve values dynamically, and the syntax does not support dynamically computed properties that I could find.

I wanted to be able to store variables that were set once when the script was evaluated (see `reset` from above) in a different area than variables that could change with every request.  In my library, I store them in a separate JS object `state`, that gets serialized and written to a postman variable when changes are made (full state object is loaded, modified, and then re-written upon change).  

For instance, if I have the following state:

```js
{"foo": "bar"}
```

Then my serialized state variable would look like:

```js
{"state": "{\"foo\": \"bar\"}"}
```

This does mean that I can't reference `{{state.foo}}`, however.  How to achieve the separate storage while allowing this ability?

My solution here was twofold:

1. **Store persistent scope in collectionVariables**
If I stored my objects in the Collection variable scope, it would be available to any interested parties.  I would then have a single `state` variable that would encompass **all** my dynamic state values, and which was retained between requests.
2. **Hydrate state variables into dynamic scope in prerequest**
Postman `pm.variables` is scoped per-request, but more importantly, it is wiped once the request Tests cleared.  If I took my state and wrote it to `pm.variables` in the collection Pre-request, the state variables would be available for the entirety of the request, and would then disappear, meaning it would always have the freshest values of state.

In the script above, you may have noticed this bit:

```js
if (app.hasUtils()) {
    app.getUtils().prerequest(pm);
}
```

When run for the collection, it simply says:

- Does the utility script exist?  Has it been fetched and evaluated?
- If so, run `prerequest()`

```js
// Utils.prerequest:
    prerequest(pm: Postman) {
        this.logger.log("Running universal pre-request", LogLevel.info, LogVerbosity.verbose);
        this.setPm(pm);
        // Confirm valid environment.
        this.env.validate(); 
        const vars: {[k:string]:any} = {};
        const state_values = this.getEnv().getState().getAll();
        Object.keys(state_values)           
            .map((k: string) => vars[k] = state_values[k]);
        Object.keys(state_values)           
            .map((k: string) => this.pm.variables.set(k, state_values[k]));
        const preference_values = this.getEnv().getPreferences().getAll();        
        
        Object.keys(preference_values)           
            .map((k: string) => vars[k] = preference_values[k]);
        Object.keys(preference_values)
            .map((k: string) => this.pm.variables.set(k, preference_values[k]));
        this.logger.log(['Available variables: ', vars], LogLevel.info, LogVerbosity.verbose);
    }
```

Most of `prerequest` involves writing values into `pm.variables` prior to the request, both my transient ones (`state`), and the ones that were established when I first evaluate the script (`preferences`) (there's one other one, `setPm(pm)`, which I'll talk about shortly).

### setPm

Another object lesson I learned is that the values in `pm` aren't necessarily reliable.  If you modify `pm` in one part of the collection, when you try to retrieve a value from it later, you may be dealing with a different object.  For this reason, I added a `setPm` method which is called in the prerequest, which simply takes whatever Postman considers the current `pm` instance, and sets it to the class internals, so that variables will be up to date.  Is this a bug with Postman?  Not sure, but this workaround works for now.

### Conclusion

This is a work in progress, so I may revisit this with subsequent entries.  I hope this was useful to folks.

### Footnotes

[^1]: Project file structure:

```bash
.
├── README.md
├── README.pdf
├── built
│   └── postman_utils.min.js
├── package.json
├── pnpm-lock.yaml
├── register.js
├── serve.js
├── src
│   ├── Environment.ts
│   ├── Helpers.ts
│   ├── Logger.ts
│   ├── Preferences.ts
│   ├── Response.ts
│   ├── State.ts
│   ├── Token.ts
│   ├── User.ts
│   ├── Utils.ts
│   └── index.ts
├── test
│   ├── BufferedLog.unit.tests.ts
│   ├── Environment.unit.tests.ts
│   ├── Helpers.unit.test.ts
│   ├── Response.unit.tests.ts
│   └── tsconfig.json
├── tsconfig.json
├── webpack.config.js
├── yarn-error.log
└── yarn.lock
```

[^2]: Webpack config:

```js
const path = require('path');

module.exports = {
    // bundling mode
    mode: 'production',

    // entry files
    entry: './src/index.ts',
    output: {
        filename: "postman_utils.min.js",
        path: path.resolve(__dirname, 'built'),
        globalObject: 'this',
        library: {
            name: "PostmanUtilsFactory",
            type: "umd"
        }
    },

    // file resolutions
    resolve: {
        extensions: ['.ts', '.js'],
    },

    // loaders
    module: {
        rules: [
            {
                test: /\.tsx?/,
                use: 'ts-loader',
                exclude: /node_modules/
            }
        ]
    }
};
```

[^3]: Javascript packages involved:

```json
{
    "devDependencies": {
        "@istanbuljs/nyc-config-typescript": "^1.0.2",
        "@testdeck/mocha": "^0.2.0",
        "@tsconfig/node16": "^1.0.2",
        "@types/google-closure-compiler": "^0.0.19",
        "@types/node": "*",
        "chai": "^4.3.6",
        "google-closure-compiler": "^20220405.0.0",
        "mocha": "^9.2.2",
        "nyc": "^15.1.0",
        "source-map-support": "^0.5.21",
        "ts-loader": "^9.2.8",
        "ts-mockito": "^2.6.1",
        "ts-node": "^10.7.0",
        "tsconfig-paths": "^3.14.1",
        "typescript": "^4.7.0-dev.20220402",
        "webpack": "^5.72.0",
        "webpack-cli": "^4.9.2"
    }
}
```

[^4]: Express server implementation:

```js
/**
 * Serves the built app_utils.js locally for testing.
 */
 const http = require("http");
 const fs = require('fs').promises;
 const host = 'localhost';
 const port = 9999;
 
 const requestListener = function (req, res) {
    fs.readFile(__dirname + '/built/postman_utils.min.js')
        .then(contents => {
            res.setHeader("Content-Type", "text/javascript");
            res.writeHead(200);
            res.end(contents);
        })
        .catch(err => {           
            const error = `Could not start server for serving built app files: ${err}.  Did you run the build task first?`;
            const json_error = JSON.stringify({
                'error': error
            });
            res.setHeader("Content-Type", "application/json");
            res.writeHead(500);
            res.end(json_error);
            console.error(error);
        })
 };
 
 const server = http.createServer(requestListener);
 server.listen(port, host, () => {
     console.log(`Server is running on http://${host}:${port}.  Press CTRL(or CMD)+C to end.`);
 });
```

[^5]: Regarding `eval` usage, I tried using the newer `Function` since `eval` is [not recommended](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/eval), but I wasn't successful in the end. May work in the future to try to make that happen.
