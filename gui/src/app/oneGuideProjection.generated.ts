// Generated from schemas/one-guide-projection.schema.json. Do not edit.

export type CategoryKey =
  'live-now' | 'starting-soon' | 'wrestling' | 'football' | 'baseball' | 'soccer' | 'movies' | 'news'

/**
 * Bounded, deterministic, read-only projection of accepted XMLTV. Cross-channel grouping, source provenance, and programme Kind are exposed only when preserved by input evidence.
 */
export interface ChannelForgeOneGuideReadProjection {
  Version: 'one-guide/v1'
  EvaluationTimeUtc: string
  Query: 'LiveNow' | 'StartingSoon' | 'Category' | 'Details'
  CategoryKey?: 'live-now' | 'starting-soon' | 'wrestling' | 'football' | 'baseball' | 'soccer' | 'movies' | 'news'
  Offset: number
  MaximumItems: number
  TotalCount: number
  ItemsTruncated: boolean
  /**
   * @maxItems 100
   */
  Items: Item[]
}
export interface Item {
  ItemId: string
  Kind: 'Programme' | 'Event' | 'Movie' | 'SeriesEpisode' | 'Other'
  Title: string
  Subtitle?: string | null
  Description?: string | null
  EpisodeNumber?: string | null
  StartUtc: string
  StopUtc: string
  Status: 'Live' | 'StartingSoon' | 'Upcoming' | 'Past'
  CategoryKeys: CategoryKey[]
  Sport: string | null
  League: string | null
  HomeParticipant: string | null
  AwayParticipant: string | null
  Promotion: null | {
    Id: string
    Name: string
  }
  OfferingCount: number
  OfferingsTruncated: boolean
  /**
   * @minItems 1
   * @maxItems 16
   */
  Offerings:
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
    | [
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        },
        {
          OfferingId: string
          SourceId: string
          SourceLabel: string
          Availability: 'GuideOnly'
          Entitlement: 'Unknown'
          Launch: {
            Kind: 'Channel'
            ChannelReference: string
          }
          DvrSupported: boolean | null
          TimeshiftSupported: boolean | null
        }
      ]
  FreshnessState: 'Current' | 'Stale' | 'Unavailable' | 'Unknown'
  ConfidenceState: 'Confirmed' | 'NeedsReview' | 'Unknown'
  ConfidenceScore: number | null
}
export type OneGuidePage = ChannelForgeOneGuideReadProjection
export type OneGuideItem = OneGuidePage['Items'][number]
export type OneGuideOffering = OneGuideItem['Offerings'][number]
export type OneGuideCategory = NonNullable<OneGuidePage['CategoryKey']>
