const req = require.context('../../icons/svg', false, /\.svg$/)
const re = /\.\/(.*)\.svg/
const requireAll = (requireContext: any) => requireContext.keys()

const icons = requireAll(req).map((str: string) => {
  return str.match(re)![1]
})

export default icons
