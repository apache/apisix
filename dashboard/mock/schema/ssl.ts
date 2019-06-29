import { Response, Request } from 'express'

const sslList = <any>[]
for (let i = 0; i <= 50; i++) {
  sslList.push({
    node: {
      value: {
        sni: "test.com"
      },
      key: "/apisix/ssl/1"
    },
    action: "get"
  })
}

export const getSSLList = (req: Request, res: Response) => {
  return res.json(sslList)
}

export const updateSSL = (req: Request, res: Response) => {
  return res.json({
    code: 2000,
    data: {
      node: {
        value: {
          sni: "test.com"
        },
        key: "/apisix/ssl/1"
      },
      action: "set"
    }
  })
}

export const getSSL = (req: Request, res: Response) => {
  return res.json({
    code: 2000,
    data: {
      node: {
        value: {
          sni: "test.com"
        },
        key: "/apisix/ssl/1"
      },
      action: "get"
    }
  })
}

export const removeSSL = (req: Request, res: Response) => {
  return res.json({
    action: "delete"
  })
}

export const createSSL = (req: Request, res: Response) => {
  return res.json({
    node: {
      value: {
        sni: "test.com"
      }
    },
    action: "create"
  })
}