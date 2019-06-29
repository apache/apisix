import { Response, Request } from 'express'

const consumerList = <any>[]
for (let i = 0; i <= 50; i++) {
  consumerList.push({
    node: {
      value: {
        username: "jack"
      }
    },
    action: "set"
  })
}

export const getConsumerList = (req: Request, res: Response) => {
  return res.json(consumerList)
}

export const updateOrCreateConsumer = (req: Request, res: Response) => {
  return res.json({
    node: {
      value: {
        username: "jack",
        plugins: {
          ['key-auth']: {
            key: "auth-one"
          }
        }
      }
    },
    action: "set"
  })
}

export const getConsumer = (req: Request, res: Response) => {
  return res.json({
    node: {
      value: {
        username: "jack",
        plugins: {
          ['key-auth']: {
            key: "auth-one"
          }
        }
      }
    },
    action: "get"
  })
}

export const removeConsumer = (req: Request, res: Response) => {
  return res.json({
    action: "delete"
  })
}
