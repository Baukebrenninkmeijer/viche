export const CounterPop = {
  updated() {
    this.el.classList.remove("counter-pop");
    void this.el.offsetWidth; // force reflow to restart animation
    this.el.classList.add("counter-pop");
    setTimeout(() => this.el.classList.remove("counter-pop"), 200);
  }
}
