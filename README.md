# @'

# \# ChannelForge

# 

# > \*\*An evidence-driven television knowledge engine.\*\*

# 

# ChannelForge is an open-source PowerShell project that transforms provider playlists into accurate, trustworthy, and deterministic television lineups.

# 

# Unlike traditional playlist editors, ChannelForge is built around \*\*verification\*\*, \*\*evidence\*\*, and \*\*recoverability\*\*.

# 

# \## Project Status

# 

# \*\*Early Alpha\*\*

# 

# Current capabilities:

# 

# \- Modular PowerShell architecture

# \- GitHub Actions CI

# \- Pester unit tests

# \- Provider configuration parsing

# \- EPG source parsing

# \- M3U playlist parsing

# \- Channel domain model

# \- BuildContext domain model

# \- Channel normalization

# \- Engineering documentation

# \- Architecture Decision Records

# 

# \## Vision

# 

# > \*\*Never guess when you can verify.\*\*

# 

# ChannelForge is designed to detect provider drift, resolve channel identity, classify channels, maintain numbering plans, monitor feed quality, and generate trusted outputs for IPTVBoss, Dispatcharr, Plex, Jellyfin, and future platforms.

# 

# \## Five Pillars

# 

# \- \*\*Truth\*\* — Facts should be supported by evidence.

# \- \*\*Trust\*\* — Automated decisions should be explainable.

# \- \*\*Recoverability\*\* — Changes should be reversible.

# \- \*\*Determinism\*\* — Same input, same output.

# \- \*\*Self-Healing\*\* — Safe repairs are automated; uncertain repairs require review.

# 

# \## Documentation

# 

# | Document | Purpose |

# |---|---|

# | docs/architecture/PROJECT\_CHARTER.md | Mission and direction |

# | docs/architecture/MANIFESTO.md | Project philosophy |

# | docs/architecture/CHANNEL\_IDENTITY\_MODEL.md | Channel identity model |

# | docs/user/QUICK\_START.md | Beginner first steps |

# | docs/reference/INSTALL.md | Setup requirements |

# | docs/developer/DEVELOPER\_GUIDE.md | Developer workflow |

# | docs/engineering/ENGINEERING\_PRINCIPLES.md | Engineering standards |

# | docs/reference/SECURITY.md | Security practices |

# | docs/developer/STYLEGUIDE.md | Coding conventions |

# | docs/developer/CONTRIBUTING.md | Contribution process |

# 

# \## Development

# 

# Use:

# 

# \- PowerShell 7+

# \- Pester 5.7.1

# \- GitHub Actions

# 

# Run tests:

# 

# ```powershell

# Invoke-Pester .\\tests\\unit

