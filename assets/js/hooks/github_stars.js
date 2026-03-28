export const GithubStars = {
  mounted() {
    fetch("https://api.github.com/repos/viche-ai/viche")
      .then(r => r.json())
      .then(d => {
        const count = d.stargazers_count
        if (typeof count === "number") {
          this.el.textContent = count >= 1000 ? (count / 1000).toFixed(1) + "k" : count
        }
      })
      .catch(() => {
        this.el.textContent = "\u2605"
      })
  }
}
