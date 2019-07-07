import { Response, Request } from 'express'

const list = ['example-plugin', 'limit-req', 'limit-count', 'key-auth', 'prometheus', 'limit-conn', 'node-status']

export const getPluginList = (req: Request, res: Response) => {
  return res.json(list)
}
