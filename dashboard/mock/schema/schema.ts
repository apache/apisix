import { Response, Request } from 'express'

export const getPluginSchema = (req: Request, res: Response) => {
    const schema = {
        test: true
    }
    return res.json(schema)
  }
  