export const wait = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));
