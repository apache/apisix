import { Response, Request } from 'express'

const consumerList = <any>[]
for (let i = 0; i <= 50; i++) {
  consumerList.push({
    node: {
      value: {
        username: "jack",
        plugins: {
          ['key-auth']: {
            key: "auth-one"
          },
          ['rate-limit']: {
            key: 'rate-limit-test'
          },
          ['rate-limit2']: {
            key: 'rate-limit-test'
          },
          ['rate-limit3']: {
            key: 'rate-limit-test'
          },
          ['rate-limit4']: {
            key: 'rate-limit-test'
          }
        }
      }
    },
    action: "get"
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
