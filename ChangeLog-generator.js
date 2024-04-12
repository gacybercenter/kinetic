const child = require("child_process");
const fs = require("fs");

const latestTag = child.execSync('git describe --long --tags').toString('utf-8').split('-')[0];
const output = child.execSync(`git log ${latestTag}..HEAD --format=%B%H----DELIMITER----`).toString("utf-8");

const commitsArray = output.split("----DELIMITER----\n")
  .map(commit => {
    const [message, sha] = commit.split("\n");

    return { sha, message };
  })
  .filter(commit => Boolean(commit.sha));

const currentChangelog = fs.readFileSync("./CHANGELOG.md", "utf-8");
const newVersion = Number(require("./package.json").version);
let newChangelog = `# Version: GCR.RC.${newVersion} (${
  new Date().toISOString().split("T")[0]
})\n\n`;

//List initialization 
const features = [];
const chores = [];
const bugs = [];
const builds = [];
const documents = [];
const general = [];

commitsArray.forEach(commit => {
  if (commit.message.startsWith("feat: ")) {
    features.push(
      `* ${commit.message.replace("feat: ", "")} ([${commit.sha.substring(
        0,
        6
      )}](https://gitlab.com/gacybercenter/orchestration/-/commit/${
        commit.sha
      }))\n`
    );
  }
  else if (commit.message.startsWith("chore: ")) {
    chores.push(
      `* ${commit.message.replace("chore: ", "")} ([${commit.sha.substring(
        0,
        6
      )}](https://gitlab.com/gacybercenter/orchestration/-/commit/${
        commit.sha
      }))\n`
    );
  }
  else if (commit.message.startsWith("fix: ")) {
    bugs.push(
      `* ${commit.message.replace("fix: ", "")} ([${commit.sha.substring(
        0,
        6
      )}](https://gitlab.com/gacybercenter/orchestration/-/commit/${
        commit.sha
      }))\n`
    );
  }
  else if (commit.message.startsWith("build: ")) {
    builds.push(
      `* ${commit.message.replace("build: ", "")} ([${commit.sha.substring(
        0,
        6
      )}](https://gitlab.com//gacybercenter/orchestration/commit/${
        commit.sha
      }))\n`
    );
  }
  else if (commit.message.startsWith("doc: ")) {
    documents.push(
      `* ${commit.message.replace("doc: ", "")} ([${commit.sha.substring(
        0,
        6
      )}](https://gitlab.com//gacybercenter/orchestration/commit/${
        commit.sha
      }))\n`
    );
  }
  else {
    general.push(
      `* ${commit.message} ([${commit.sha.substring(
        0,
        6
      )}](https://gitlab.com//gacybercenter/orchestration/commit/${
        commit.sha
      }))\n`
    );
  }
});

if (features.length) {
  newChangelog += `## Feature\n`;
  features.forEach(feature => {
    newChangelog += feature;
  });
  newChangelog += '\n';
}

if (chores.length) {
  newChangelog += `## Chore\n`;
  chores.forEach(chore => {
    newChangelog += chore;
  });
  newChangelog += '\n';
}

if (bugs.length) {
    newChangelog += `## Bug Fix\n`;
    bugs.forEach(bug => {
      newChangelog += bug;
    });
    newChangelog += '\n';
}

if (builds.length) {
  newChangelog += `## System Configuration\n`;
  builds.forEach(build => {
    newChangelog += build;
  });
  newChangelog += '\n';
}

if (documents.length) {
  newChangelog += `## Documentation\n`;
  documents.forEach(doc => {
    newChangelog += doc;
  });
  newChangelog += '\n';
}

if (general.length) {
  newChangelog += `## Other\n`;
  general.forEach(gen => {
    newChangelog += gen;
  });
  newChangelog += '\n';
}

// create a new commit
child.execSync('git add .');
child.execSync(`git commit -m "chore: Bump to version GCR.RC.${newVersion}"`);
child.execSync('git push');

// prepend the newChangelog to the current one
fs.writeFileSync("./CHANGELOG.md", `${newChangelog}${currentChangelog}`);

child.execSync('git add .');
child.execSync(`git commit -m "chore: Automated ChangeLog Content Update."`);
child.execSync('git push');

// tag the commit
child.execSync(`git tag -a -m "Tag for version GCR.RC.${newVersion}" GCR.RC.${newVersion}`);
child.execSync(`git push origin --tags`);
