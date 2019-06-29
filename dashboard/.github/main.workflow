workflow "Deploy on GitHub Pages" {
  on = "push"
  resolves = ["Deploy"]
}

action "Filters for GitHub Actions" {
  uses = "actions/bin/filter@master"
  args = "branch master"
}

 action "Yarn install" {
  uses = "borales/actions-yarn@master"
  needs = ["Filters for GitHub Actions"]
  args = "install"
}

 action "Yarn build" {
  uses = "borales/actions-yarn@master"
  needs = ["Yarn install"]
  args = "build:prod"
}

action "Deploy" {
  uses = "maxheld83/ghpages@v0.2.1"
  needs = ["Yarn build"]
  env = {
    BUILD_DIR = "dist/"
  }
  secrets = ["GH_PAT"]
}
